import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateTopicCoverUploadInputSchema } from "../schemas/callableInputs";
import { presignPutUrl, publicUrlFor, R2_SECRETS } from "../lib/r2";

const COVER_UPLOAD_TTL_SECONDS = 30 * 60;

/**
 * The topic-editor twin of `createThumbnailUpload` — same presign shape,
 * different ownership check (topic rather than video) and key prefix. Kept
 * separate rather than overloading the video one with an optional topicId:
 * the two have genuinely different authorization rules, and collapsing them
 * would mean a branch deciding which check to run on every call.
 *
 * Unlike the video/thumbnail pair there's no `finalize` step — the topic doc
 * is client-writable by its owner (see firestore.rules), so the editor sets
 * `coverImageURL` itself once the PUT succeeds.
 */
export const createTopicCoverUpload = onCall({ secrets: R2_SECRETS }, async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(CreateTopicCoverUploadInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";

  const topicSnap = await db.collection("topics").doc(input.topicId).get();
  if (!topicSnap.exists) {
    throw new HttpsError("not-found", "Topic not found.");
  }
  const topic = topicSnap.data()!;
  if (topic.createdBy !== uid && !isAdmin) {
    throw new HttpsError("permission-denied", "You do not own this topic.");
  }

  const r2Key = `covers/${input.topicId}.jpg`;
  const uploadURL = await presignPutUrl(r2Key, input.contentType, COVER_UPLOAD_TTL_SECONDS);
  const coverImageURL = publicUrlFor(r2Key);
  const expiresAt = Date.now() + COVER_UPLOAD_TTL_SECONDS * 1000;

  return { uploadURL, r2Key, coverImageURL, expiresAt };
});
