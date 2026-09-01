import { defineSecret, defineString } from "firebase-functions/params";
import { GolpoTiming } from "./tiers";

/**
 * GolpoAI (video.golpoai.com/api-docs) — the render backend, per
 * prompts/phase-07-lessons-on-demand.md §2. One account Shui bills, not a
 * per-learner key. Base URL is a plain string (not sensitive) so staging/
 * prod can point at different GolpoAI environments without a secret rotation.
 */
export const golpoApiKey = defineSecret("GOLPO_API_KEY");
export const golpoApiBaseUrl = defineString("GOLPO_API_BASE_URL", { default: "https://video.golpoai.com/api/v2" });

export const GOLPO_SECRETS = [golpoApiKey];

/** ~1,050 characters per minute of `timing` — the real Script Mode budget the phase doc cites. */
export const GOLPO_CHARS_PER_MINUTE = 1050;

export function scriptCharBudget(timing: GolpoTiming): number {
  return Math.floor(parseFloat(timing) * GOLPO_CHARS_PER_MINUTE);
}

export interface GolpoGenerateRequest {
  customScript: string;
  timing: GolpoTiming;
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
    const res = await fetch(`${golpoApiBaseUrl.value()}/videos/generate`, {
      method: "POST",
      headers: { "x-api-key": golpoApiKey.value(), "content-type": "application/json" },
      body: JSON.stringify({
        custom_script: req.customScript,
        timing: req.timing,
        video_orientation: "vertical",
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
    if (data.status === "failed") {
      return { status: "failed", message: data.error ?? "GolpoAI reported a render failure with no message." };
    }
    return { status: data.status === "generating" ? "generating" : "queued" };
  }
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
