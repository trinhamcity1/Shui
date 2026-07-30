import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateThumbnailUploadInputSchema } from "../schemas/callableInputs";
import { presignPutUrl, publicUrlFor, R2_SECRETS } from "../lib/r2";

const THUMBNAIL_UPLOAD_TTL_SECONDS = 30 * 60;

export const createThumbnailUpload = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(CreateThumbnailUploadInputSchema, request.data);
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

  const r2Key = `thumbs/${input.videoId}.jpg`;
  const uploadURL = await presignPutUrl(r2Key, input.contentType, THUMBNAIL_UPLOAD_TTL_SECONDS);
  const thumbnailURL = publicUrlFor(r2Key);
  const expiresAt = Date.now() + THUMBNAIL_UPLOAD_TTL_SECONDS * 1000;

  return { uploadURL, r2Key, thumbnailURL, expiresAt };
});
