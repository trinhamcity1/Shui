import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ReorderTopicVideosInputSchema, UpdateVideoMetadataInputSchema } from "../schemas/callableInputs";

/**
 * Every client write to `videos` is denied by rules — a creator dragging
 * rows in the topic editor still has to come through here. Takes the whole
 * intended order rather than a (from, to) pair so the write is idempotent
 * and doesn't depend on the client and server agreeing about the starting
 * state.
 */
export const reorderTopicVideos = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ReorderTopicVideosInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";

  const duplicates = input.videoIds.length !== new Set(input.videoIds).size;
  if (duplicates) {
    throw new HttpsError("invalid-argument", "The same video appears more than once in the requested order.");
  }

  await db.runTransaction(async (t) => {
    const topicRef = db.collection("topics").doc(input.topicId);
    const topicSnap = await t.get(topicRef);
    if (!topicSnap.exists) {
      throw new HttpsError("not-found", "Topic not found.");
    }
    const topic = topicSnap.data()!;
    if (topic.createdBy !== uid && !isAdmin) {
      throw new HttpsError("permission-denied", "You do not own this topic.");
    }

    // Read every video in the topic, not just the ones named in the request
    // — a reorder that silently dropped a row from the topic (or smuggled in
    // a video belonging to a different topic) would corrupt the feed's
    // ordering, so both are rejected outright rather than partially applied.
    const videosSnap = await t.get(db.collection("videos").where("topicId", "==", input.topicId));
    const live = videosSnap.docs.filter((d) => d.data().isDeleted === false);
    const liveIds = new Set(live.map((d) => d.id));

    for (const videoId of input.videoIds) {
      if (!liveIds.has(videoId)) {
        throw new HttpsError("invalid-argument", `Video ${videoId} is not part of this topic.`);
      }
    }
    if (input.videoIds.length !== live.length) {
      throw new HttpsError(
        "failed-precondition",
        "This topic's videos changed while you were reordering — reopen the topic and try again."
      );
    }

    input.videoIds.forEach((videoId, index) => {
      t.update(db.collection("videos").doc(videoId), {
        order: index,
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  });

  return { ordered: input.videoIds.length };
});

export const updateVideoMetadata = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(UpdateVideoMetadataInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";

  const updates: Record<string, unknown> = {};
  if (input.title !== undefined) updates.title = input.title;
  if (input.description !== undefined) updates.description = input.description;
  if (input.transcript !== undefined) updates.transcript = input.transcript;
  if (Object.keys(updates).length === 0) {
    throw new HttpsError("invalid-argument", "Nothing to update.");
  }

  const videoRef = db.collection("videos").doc(input.videoId);
  await db.runTransaction(async (t) => {
    const videoSnap = await t.get(videoRef);
    if (!videoSnap.exists) {
      throw new HttpsError("not-found", "Video not found.");
    }
    const video = videoSnap.data()!;
    if (video.createdBy !== uid && !isAdmin) {
      throw new HttpsError("permission-denied", "You do not own this video.");
    }
    t.update(videoRef, { ...updates, updatedBy: uid, updatedAt: FieldValue.serverTimestamp() });
  });

  return { updated: Object.keys(updates) };
});
