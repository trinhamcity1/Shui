import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ToggleLikeInputSchema } from "../schemas/callableInputs";
import { applyLikeRefundIfEligible } from "../lib/credits";

export const toggleLike = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ToggleLikeInputSchema, request.data);

  const videoRef = db.collection("videos").doc(input.videoId);
  const likeRef = db.collection("users").doc(uid).collection("likes").doc(input.videoId);

  const liked = await db.runTransaction(async (t) => {
    const [videoSnap, likeSnap] = await Promise.all([t.get(videoRef), t.get(likeRef)]);
    if (!videoSnap.exists) {
      throw new HttpsError("not-found", "Video not found.");
    }
    const video = videoSnap.data()!;

    if (likeSnap.exists) {
      t.delete(likeRef);
      t.update(videoRef, { likeCount: FieldValue.increment(-1) });
      return false;
    }

    t.set(likeRef, {
      videoId: input.videoId,
      topicId: video.topicId,
      videoTitle: video.title,
      thumbnailURL: video.thumbnailURL ?? null,
      likedAt: FieldValue.serverTimestamp(),
    });
    t.update(videoRef, { likeCount: FieldValue.increment(1) });

    // Alabaster/Pyramidion's like-refund (phase-07 §4) — a no-op for every
    // other tier, and only ever evaluated on a fresh like, never an
    // unlike. Runs in this same transaction since it's derived from the
    // exact counter change this transaction is already making.
    if (video.createdBy && video.createdBy !== uid) {
      await applyLikeRefundIfEligible(t, video.createdBy, videoRef, {
        likeCount: video.likeCount ?? 0,
        refundClaimed: video.refundClaimed ?? false,
      });
    }

    return true;
  });

  return { liked };
});
