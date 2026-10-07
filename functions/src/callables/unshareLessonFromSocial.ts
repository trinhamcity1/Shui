import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ShareLessonToSocialInputSchema } from "../schemas/callableInputs";

/**
 * The reverse of shareLessonToSocial.ts. Flips this one video back to
 * private and clears `sharedToSocial` — deliberately not touched: the
 * parent topic's `visibility`, which stays public once any lesson under it
 * has ever been shared. That's safe to leave alone: every sibling video
 * under the same personal topic is independently gated by its own
 * `visibility` field (shareLessonToSocial.ts's own doc comment), so a
 * public topic with this one video back to private just means this video
 * is private again, not a leak. Clearing `sharedToSocial` (rather than just
 * flipping visibility) matters for re-sharing later: shareLessonToSocial
 * short-circuits as a no-op once it sees `sharedToSocial === true`, so
 * leaving it `true` here would make a future re-share silently fail to
 * actually flip visibility back to public.
 */
export async function runUnshareLessonFromSocial(uid: string, videoId: string): Promise<{ shared: boolean }> {
  const videoRef = db.collection("videos").doc(videoId);
  const snap = await videoRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Lesson not found.");
  }
  const video = snap.data()!;
  if (video.createdBy !== uid) {
    throw new HttpsError("permission-denied", "This is not your lesson.");
  }
  if (video.sharedToSocial !== true) {
    return { shared: false }; // idempotent
  }

  await videoRef.update({
    visibility: "private",
    sharedToSocial: false,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { shared: false };
}

export const unshareLessonFromSocial = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ShareLessonToSocialInputSchema, request.data);
  return runUnshareLessonFromSocial(uid, input.videoId);
});
