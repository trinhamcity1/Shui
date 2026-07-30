import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { FinalizeVideoUploadInputSchema } from "../schemas/callableInputs";
import { headObject, publicUrlFor, R2_SECRETS } from "../lib/r2";

export const finalizeVideoUpload = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(FinalizeVideoUploadInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";

  const videoRef = db.collection("videos").doc(input.videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Video not found.");
  }
  const video = videoSnap.data()!;
  if (video.createdBy !== uid && !isAdmin) {
    throw new HttpsError("permission-denied", "You do not own this video.");
  }

  const headResult = await headObject(video.r2Key);
  if (!headResult) {
    await videoRef.update({
      status: "failed",
      statusMessage: "No file was found at the expected upload location.",
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError(
      "failed-precondition",
      "Upload not found in storage — the file never reached R2."
    );
  }

  const topicRef = db.collection("topics").doc(video.topicId);
  const playbackURL = publicUrlFor(video.r2Key);
  const thumbnailURL = input.thumbnailR2Key ? publicUrlFor(input.thumbnailR2Key) : video.thumbnailURL ?? null;

  await db.runTransaction(async (t) => {
    const topicSnap = await t.get(topicRef);
    const topic = topicSnap.exists ? topicSnap.data()! : null;

    let readyDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    if (topic) {
      const readyVideosQuery = db
        .collection("videos")
        .where("topicId", "==", video.topicId)
        .where("status", "==", "ready")
        .where("isDeleted", "==", false);
      const readySnap = await t.get(readyVideosQuery);
      readyDocs = readySnap.docs;
    }

    t.update(videoRef, {
      status: "ready",
      statusMessage: null,
      sizeBytes: headResult.sizeBytes,
      playbackURL,
      thumbnailURL,
      transcript: input.transcript ?? video.transcript ?? null,
      topicVisibility: topic?.visibility ?? video.topicVisibility ?? "private",
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (topic) {
      const totalDurationSec =
        readyDocs.reduce((sum, d) => sum + (d.data().durationSeconds ?? 0), 0) + video.durationSeconds;
      const videoCount = readyDocs.length + 1;
      t.update(topicRef, { videoCount, totalDurationSec, updatedAt: FieldValue.serverTimestamp() });
    }
  });

  return { videoId: input.videoId, status: "ready", playbackURL };
});
