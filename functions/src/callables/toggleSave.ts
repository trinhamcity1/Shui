import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ToggleSaveInputSchema } from "../schemas/callableInputs";

/**
 * A private bookmark, not a public engagement signal — mirrors toggleLike's
 * shape exactly (same transaction pattern, same denormalized doc under the
 * user), but deliberately doesn't touch a video-level counter the way a
 * like does. Nothing else in the app needs to know how many people saved a
 * video; only the saver does.
 */
export const toggleSave = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ToggleSaveInputSchema, request.data);

  const videoRef = db.collection("videos").doc(input.videoId);
  const saveRef = db.collection("users").doc(uid).collection("savedVideos").doc(input.videoId);

  const saved = await db.runTransaction(async (t) => {
    const [videoSnap, saveSnap] = await Promise.all([t.get(videoRef), t.get(saveRef)]);
    if (!videoSnap.exists) {
      throw new HttpsError("not-found", "Video not found.");
    }
    const video = videoSnap.data()!;

    if (saveSnap.exists) {
      t.delete(saveRef);
      return false;
    }

    t.set(saveRef, {
      videoId: input.videoId,
      topicId: video.topicId,
      videoTitle: video.title,
      thumbnailURL: video.thumbnailURL ?? null,
      savedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });

  return { saved };
});
