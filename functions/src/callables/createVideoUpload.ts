import { onCall, HttpsError } from "firebase-functions/v2/https";
import { randomUUID } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateVideoUploadInputSchema } from "../schemas/callableInputs";
import { presignPutUrl, publicUrlFor, R2_SECRETS } from "../lib/r2";

const UPLOAD_URL_TTL_SECONDS = 30 * 60;

export const createVideoUpload = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = requireRole(request, ["creator", "admin"]);
  const input = parseInput(CreateVideoUploadInputSchema, request.data);

  const topicRef = db.collection("topics").doc(input.topicId);
  const topicSnap = await topicRef.get();
  if (!topicSnap.exists) {
    throw new HttpsError("not-found", "Topic not found.");
  }
  const topic = topicSnap.data()!;
  const isAdmin = request.auth!.token.role === "admin";
  if (topic.createdBy !== uid && !isAdmin) {
    throw new HttpsError("permission-denied", "You do not own this topic.");
  }

  const existingCountSnap = await db
    .collection("videos")
    .where("topicId", "==", input.topicId)
    .count()
    .get();
  const nextOrder = existingCountSnap.data().count;

  const videoId = randomUUID();
  const r2Key = `videos/${videoId}.mp4`;
  const playbackURL = publicUrlFor(r2Key);

  await db
    .collection("videos")
    .doc(videoId)
    .set({
      topicId: input.topicId,
      topicTitle: topic.title,
      categoryId: topic.categoryId,
      topicVisibility: topic.visibility,
      title: input.title,
      description: input.description ?? "",
      order: nextOrder,
      r2Key,
      playbackURL,
      thumbnailURL: null,
      durationSeconds: input.durationSeconds,
      aspectRatio: input.aspectRatio,
      sizeBytes: input.sizeBytes,
      transcript: null,
      visibility: "private",
      status: "uploading",
      statusMessage: null,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      publishedAt: null,
      hasQuiz: false,
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      completionCount: 0,
      isDeleted: false,
    });

  const uploadURL = await presignPutUrl(r2Key, input.contentType, UPLOAD_URL_TTL_SECONDS);
  const expiresAt = Date.now() + UPLOAD_URL_TTL_SECONDS * 1000;

  return { videoId, uploadURL, r2Key, playbackURL, expiresAt };
});
