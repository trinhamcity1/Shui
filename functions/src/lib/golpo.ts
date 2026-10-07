import { defineSecret, defineString } from "firebase-functions/params";
import { GolpoTiming } from "./tiers";
import { GolpoSettings } from "./golpoCapabilities";

/**
 * GolpoAI (docs at video.golpoai.com/api-docs — the render backend, per
 * prompts/phase-07-lessons-on-demand.md §2. One account Shui bills, not a
 * per-learner key. Base URL is a plain string (not sensitive) so staging/
 * prod can point at different GolpoAI environments without a secret rotation.
 *
 * IMPORTANT: the real API lives at `api.golpoai.com`, a *different* host
 * than the docs/dashboard site (`video.golpoai.com`) — confirmed 2026-10 by
 * directly curling both with a real key: `video.golpoai.com` either 404s
 * (its own Next.js frontend intercepting the request) or returns a generic
 * "Authentication required" regardless of key validity, while
 * `api.golpoai.com` is the real backend that actually recognizes it. The
 * wrong host was configured as the default since Phase 7 — every real call
 * this app has ever made was hitting the wrong domain.
 */
export const golpoApiKey = defineSecret("GOLPO_API_KEY");
export const golpoApiBaseUrl = defineString("GOLPO_API_BASE_URL", { default: "https://api.golpoai.com/api/v2" });

export const GOLPO_SECRETS = [golpoApiKey];

/** ~1,050 characters per minute of `timing` — the real Script Mode budget the phase doc cites. */
export const GOLPO_CHARS_PER_MINUTE = 1050;

export function scriptCharBudget(timing: GolpoTiming): number {
  return Math.floor(parseFloat(timing) * GOLPO_CHARS_PER_MINUTE);
}

export interface GolpoGenerateRequest {
  /**
   * The real v2 endpoint docs (video.golpoai.com/api-docs/endpoints/v2,
   * verified 2026-10) mark `prompt` as required even in Script Mode —
   * `custom_script` alone isn't enough to pass validation. The learner's raw
   * topic string is the natural value: it's already "the main prompt/topic"
   * in Golpo's own words, and Golpo only reads it as a fallback label since
   * `custom_script` is what actually drives the render.
   */
  topic: string;
  customScript: string;
  timing: GolpoTiming;
  settings: GolpoSettings;
}

export interface GolpoGenerateResult {
  jobId: string;
  videoId: string;
}

export type GolpoStatus =
  | { status: "queued" }
  | { status: "generating" }
  | { status: "completed"; videoUrl: string }
  | { status: "failed"; message: string };

/**
 * The one seam every real GolpoAI call goes through — callables never talk
 * to `fetch` directly, so unit tests can substitute `FakeGolpoClient` and
 * stay fast, free, and deterministic. Same reasoning as ModelClient
 * (functions/src/ai/modelClient.ts) for the Anthropic side.
 */
export interface GolpoClient {
  generate(req: GolpoGenerateRequest): Promise<GolpoGenerateResult>;
  checkStatus(jobId: string): Promise<GolpoStatus>;
}

export class GolpoRestClient implements GolpoClient {
  async generate(req: GolpoGenerateRequest): Promise<GolpoGenerateResult> {
    const { settings } = req;
    const res = await fetch(`${golpoApiBaseUrl.value()}/videos/generate`, {
      method: "POST",
      headers: { "x-api-key": golpoApiKey.value(), "content-type": "application/json" },
      body: JSON.stringify({
        prompt: req.topic,
        custom_script: req.customScript,
        timing: req.timing,
        video_orientation: "vertical",
        golpo_video_engine: settings.engine,
        canvas_style_variant: settings.canvasStyleVariant,
        sketch_style_variant: settings.sketchStyleVariant,
        pen_animation_style: settings.penAnimationStyle,
        scene_pacing: settings.scenePacing,
        narration_voice: settings.voice,
        background_track: settings.musicTrack,
        visual_instructions: settings.visualInstructions,
        narration_instructions: settings.narrationInstructions,
      }),
    });
    if (!res.ok) {
      throw new Error(`GolpoAI generate failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { job_id: string; video_id: string };
    return { jobId: data.job_id, videoId: data.video_id };
  }

  async checkStatus(jobId: string): Promise<GolpoStatus> {
    const res = await fetch(`${golpoApiBaseUrl.value()}/videos/status/${jobId}`, {
      headers: { "x-api-key": golpoApiKey.value() },
    });
    if (!res.ok) {
      throw new Error(`GolpoAI status check failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { status: string; video_url?: string; error?: string };
    if (data.status === "completed") {
      if (!data.video_url) {
        throw new Error("GolpoAI reported a completed job with no video_url — treat as a failure, not a retry.");
      }
      return { status: "completed", videoUrl: data.video_url };
    }
    // Never forward the render backend's own error text to the caller —
    // that text is third-party, unpredictable, and could name the vendor
    // (checked into git or not, this app never shows a learner "Golpo" or
    // "Anthropic"; see checkOnDemandLessonStatus.ts, which is what actually
    // returns this to the client). The real text still reaches Cloud
    // Functions logs, which is where debugging a real failure belongs.
    if (data.status === "failed") {
      if (data.error) console.error(`GolpoAI render failed for job ${jobId}: ${data.error}`);
      return { status: "failed", message: "Something went wrong while creating this video." };
    }
    return { status: data.status === "generating" ? "generating" : "queued" };
  }
}

/**
 * `GET /users/credits` (video.golpoai.com/api-docs/endpoints/v2, verified
 * 2026-10) — the real remaining-balance endpoint, confirmed to exist after
 * all, which `providerBudgets.ts` now reads instead of an admin-maintained
 * ledger. Response shape: `{ "plan": "api_only", "credits": 124.5, "status":
 * "active" }` — `credits` is whole/fractional dollars, not cents.
 */
export async function fetchGolpoCreditsCents(): Promise<number> {
  const res = await fetch(`${golpoApiBaseUrl.value()}/users/credits`, {
    headers: { "x-api-key": golpoApiKey.value() },
  });
  if (!res.ok) {
    throw new Error(`GolpoAI credits check failed: ${res.status} ${await res.text()}`);
  }
  const data = (await res.json()) as { credits: number };
  return Math.round(data.credits * 100);
}

/** Scripted responses for tests — never calls the real API. */
export class FakeGolpoClient implements GolpoClient {
  private statusQueue: GolpoStatus[];

  constructor(
    private readonly result: GolpoGenerateResult = { jobId: "fake-job-1", videoId: "fake-video-1" },
    statusSequence: GolpoStatus[] = [{ status: "completed", videoUrl: "https://fake.example/video.mp4" }]
  ) {
    this.statusQueue = [...statusSequence];
  }

  async generate(): Promise<GolpoGenerateResult> {
    return this.result;
  }

  async checkStatus(): Promise<GolpoStatus> {
    return this.statusQueue.length > 1 ? this.statusQueue.shift()! : this.statusQueue[0]!;
  }
}
