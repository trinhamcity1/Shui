import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ShareLessonToSocialInputSchema } from "../schemas/callableInputs";

/**
 * Private by default, explicit opt-in to Social (phase-07 §1/§6). Flips the
 * personal topic to public once (idempotent — subsequent shares are a
 * no-op there) and this one video's own visibility to public. Every other
 * lesson under the same personal topic stays private because its own
 * `visibility` field still gates it independently — the exact reason Phase 1
 * denormalized both `visibility` and `topicVisibility` onto every video
 * instead of only checking the parent. No rules change required for this.
 */
export async function runShareLessonToSocial(uid: string, videoId: string): Promise<{ shared: boolean }> {
  const videoRef = db.collection("videos").doc(videoId);
  const snap = await videoRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Lesson not found.");
  }
  const video = snap.data()!;
  if (video.createdBy !== uid) {
    throw new HttpsError("permission-denied", "This is not your lesson.");
  }
  if (video.status !== "ready") {
    throw new HttpsError("failed-precondition", "Only a finished lesson can be shared.");
  }
  if (video.sharedToSocial === true) {
    return { shared: true }; // idempotent
  }

  await db.collection("topics").doc(video.topicId).set(
    { visibility: "public", updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
  await videoRef.update({
    visibility: "public",
    topicVisibility: "public",
    sharedToSocial: true,
    sharedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { shared: true };
}

export const shareLessonToSocial = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ShareLessonToSocialInputSchema, request.data);
  return runShareLessonToSocial(uid, input.videoId);
});
