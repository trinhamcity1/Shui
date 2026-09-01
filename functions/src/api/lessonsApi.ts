import { onRequest, HttpsError, Request } from "firebase-functions/v2/https";
import { Response } from "express";
import { db } from "../lib/admin";
import { readWallet } from "../lib/credits";
import { tierOf } from "../lib/tiers";
import { resolvePlaybackUrl } from "../lib/onDemandVideo";
import { resolveApiKey, checkAndConsumeRateLimit, API_KEY_RATE_LIMIT_PER_HOUR } from "../lib/apiKeys";
import { statusForFunctionsErrorCode, apiError } from "./httpResponse";
import { runCreateOnDemandLesson } from "../callables/createOnDemandLesson";
import { runCheckOnDemandLessonStatus } from "../callables/checkOnDemandLessonStatus";
import { AnthropicModelClient, AI_SECRETS } from "../ai/modelClient";
import { GolpoRestClient, GOLPO_SECRETS } from "../lib/golpo";
import { FakeWatermarkProcessor } from "../lib/watermark";

/**
 * Phase-07 §8's developer API: `POST /v1/lessons` and `GET /v1/lessons/{id}`,
 * both sub-paths of this one function's URL (no Hosting rewrite configured —
 * a developer calls e.g. `https://{region}-{project}.cloudfunctions.net/
 * lessonsApi/v1/lessons`). Auth is a `x-api-key` header resolved to a uid via
 * lib/apiKeys.ts's hashed lookup — no Firebase Auth token on this path at
 * all. Wraps the exact same `runCreateOnDemandLesson`/
 * `runCheckOnDemandLessonStatus` core the app callables use ("one
 * implementation, two entry points" — §1) rather than reimplementing the
 * pipeline.
 */
export const lessonsApi = onRequest({ secrets: [...AI_SECRETS, ...GOLPO_SECRETS] }, async (req: Request, res: Response) => {
  const rawKey = req.header("x-api-key");
  if (!rawKey) {
    res.status(401).json(apiError("unauthorized", "Missing x-api-key header."));
    return;
  }

  const resolved = await resolveApiKey(rawKey);
  if (!resolved) {
    res.status(401).json(apiError("unauthorized", "Invalid or revoked API key."));
    return;
  }

  const rate = await checkAndConsumeRateLimit(resolved.keyId);
  if (!rate.allowed) {
    res.set("Retry-After", String(rate.retryAfterSeconds ?? 3600));
    res
      .status(429)
      .json(apiError("rate_limited", `This key is limited to ${API_KEY_RATE_LIMIT_PER_HOUR} requests/hour — try again shortly.`));
    return;
  }

  const path = req.path.replace(/\/+$/, "") || "/";

  try {
    if (req.method === "POST" && (path === "/v1/lessons" || path === "/")) {
      await handleCreateLesson(resolved.uid, req, res);
      return;
    }

    const statusMatch = path.match(/^\/v1\/lessons\/([^/]+)$/);
    if (req.method === "GET" && statusMatch) {
      await handleGetLesson(resolved.uid, statusMatch[1]!, res);
      return;
    }

    res.status(404).json(apiError("not_found", "Unknown endpoint. Expected POST /v1/lessons or GET /v1/lessons/{id}."));
  } catch (err) {
    if (err instanceof HttpsError) {
      res.status(statusForFunctionsErrorCode(err.code)).json(apiError(err.code, err.message));
      return;
    }
    console.error("lessonsApi unhandled error", err);
    res.status(500).json(apiError("internal", "Unexpected server error."));
  }
});

async function handleCreateLesson(uid: string, req: Request, res: Response): Promise<void> {
  const topic = (req.body as { topic?: unknown } | undefined)?.topic;
  if (typeof topic !== "string" || topic.trim().length === 0 || topic.length > 300) {
    res.status(400).json(apiError("invalid_argument", "`topic` is required and must be 1-300 characters."));
    return;
  }

  const result = await runCreateOnDemandLesson(
    uid,
    topic,
    { modelClient: new AnthropicModelClient(), golpoClient: new GolpoRestClient() },
    true // originatedFromApi
  );
  res.status(202).json({ id: result.videoId, status: result.status });
}

async function handleGetLesson(uid: string, videoId: string, res: Response): Promise<void> {
  const result = await runCheckOnDemandLessonStatus(uid, videoId, {
    golpoClient: new GolpoRestClient(),
    // Same documented gap as the app callable (functions/src/lib/watermark.ts) —
    // not verified against real ffmpeg in this sandbox.
    watermarkProcessor: new FakeWatermarkProcessor(),
  });

  if (result.status !== "ready") {
    res.status(200).json({ id: videoId, status: result.status, message: result.message ?? null });
    return;
  }

  // runCheckOnDemandLessonStatus only returns a status — the app's iOS
  // client reads the video doc directly from Firestore for the URL, but a
  // developer-API consumer has no Firestore access at all, so this fetches
  // the doc itself and resolves the URL against the *caller's own* current
  // tier (never the tier they had when the lesson was generated).
  const [snap, wallet] = await Promise.all([db.collection("videos").doc(videoId).get(), readWallet(uid)]);
  const video = snap.data();
  const videoUrl = video ? resolvePlaybackUrl(video as { playbackURL: string | null; watermarkedPlaybackURL: string | null }, tierOf(wallet.tier)) : null;

  res.status(200).json({
    id: videoId,
    status: "ready",
    videoUrl,
    durationSeconds: video?.durationSeconds ?? null,
  });
}
