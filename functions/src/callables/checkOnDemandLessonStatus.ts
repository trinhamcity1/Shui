import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CheckOnDemandLessonStatusInputSchema } from "../schemas/callableInputs";
import { refundLesson } from "../lib/credits";
import { GolpoClient, GolpoRestClient, GolpoStatus, GOLPO_SECRETS } from "../lib/golpo";
import { WatermarkProcessor, FakeWatermarkProcessor } from "../lib/watermark";
import { writeLessonCache } from "../lib/lessonCache";

export interface CheckOnDemandLessonStatusResult {
  status: "generating" | "ready" | "failed";
  message?: string;
}

/**
 * The real work, factored out from the `onCall` wrapper so tests can supply
 * fakes for both the GolpoAI client and the watermark processor.
 */
export async function runCheckOnDemandLessonStatus(
  uid: string,
  videoId: string,
  deps: { golpoClient: GolpoClient; watermarkProcessor: WatermarkProcessor }
): Promise<CheckOnDemandLessonStatusResult> {
  const videoRef = db.collection("videos").doc(videoId);
  const snap = await videoRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Lesson not found.");
  }
  const video = snap.data()!;
  if (video.createdBy !== uid) {
    throw new HttpsError("permission-denied", "This is not your lesson.");
  }

  // Idempotent — the client may call this more than once for the same
  // terminal state (backgrounded app, relaunch, a second poll tick that
  // raced the first one's response).
  if (video.status === "ready") return { status: "ready" };
  if (video.status === "failed") return { status: "failed", message: video.statusMessage ?? undefined };
  if (video.status !== "generating") {
    throw new HttpsError("failed-precondition", `Unexpected lesson status: ${video.status}`);
  }

  const golpoStatus: GolpoStatus = await deps.golpoClient.checkStatus(video.golpoJobId);

  if (golpoStatus.status === "queued" || golpoStatus.status === "generating") {
    return { status: "generating" };
  }

  if (golpoStatus.status === "failed") {
    await videoRef.update({
      status: "failed",
      statusMessage: golpoStatus.message,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await refundLesson(uid, video.costChargedCents ?? 0, videoId);
    return { status: "failed", message: golpoStatus.message };
  }

  // completed — both URLs are always written; which one a viewer gets is
  // decided at access time by *their own* current tier (phase-07 §4), not
  // baked in here based on the owner's tier at generation time.
  const watermarked = await deps.watermarkProcessor.applyWatermark(golpoStatus.videoUrl, `videos/${videoId}`);
  const durationSeconds = Math.round(parseFloat(video.timing) * 60);

  await videoRef.update({
    status: "ready",
    playbackURL: golpoStatus.videoUrl,
    watermarkedPlaybackURL: watermarked.watermarkedUrl,
    durationSeconds,
    publishedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  if (!video.generatedFromCache && video.rawTopic) {
    await writeLessonCache(video.rawTopic, video.timing, {
      canonicalTopic: video.rawTopic,
      sourceVideoId: videoId,
      categoryId: video.categoryId,
      timing: video.timing,
    });
  }

  return { status: "ready" };
}

export const checkOnDemandLessonStatus = onCall({ secrets: GOLPO_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(CheckOnDemandLessonStatusInputSchema, request.data);
  return runCheckOnDemandLessonStatus(uid, input.videoId, {
    golpoClient: new GolpoRestClient(),
    // TODO: swap for the real ffmpeg/Cloud Run implementation once it's
    // built and verified against a real GolpoAI render — see
    // functions/src/lib/watermark.ts's own header note.
    watermarkProcessor: new FakeWatermarkProcessor(),
  });
});
