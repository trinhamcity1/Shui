import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import {
  SoftDeleteCommentInputSchema,
  SoftDeleteTopicInputSchema,
  SoftDeleteVideoInputSchema,
} from "../schemas/callableInputs";

export const softDeleteTopic = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SoftDeleteTopicInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";
  const topicRef = db.collection("topics").doc(input.topicId);

  await db.runTransaction(async (t) => {
    const topicSnap = await t.get(topicRef);
    if (!topicSnap.exists) {
      throw new HttpsError("not-found", "Topic not found.");
    }
    const topic = topicSnap.data()!;
    if (topic.createdBy !== uid && !isAdmin) {
      throw new HttpsError("permission-denied", "You do not own this topic.");
    }

    const videosQuery = db.collection("videos").where("topicId", "==", input.topicId);
    const videosSnap = await t.get(videosQuery);

    t.update(topicRef, { isDeleted: true, updatedAt: FieldValue.serverTimestamp() });
    for (const videoDoc of videosSnap.docs) {
      t.update(videoDoc.ref, { isDeleted: true, updatedAt: FieldValue.serverTimestamp() });
    }
  });

  return { deleted: true };
});

export const softDeleteVideo = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SoftDeleteVideoInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";
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
    t.update(videoRef, { isDeleted: true, updatedAt: FieldValue.serverTimestamp() });
  });

  return { deleted: true };
});

export const softDeleteComment = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SoftDeleteCommentInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";
  const commentRef = db
    .collection("videos")
    .doc(input.videoId)
    .collection("comments")
    .doc(input.commentId);

  await db.runTransaction(async (t) => {
    const commentSnap = await t.get(commentRef);
    if (!commentSnap.exists) {
      throw new HttpsError("not-found", "Comment not found.");
    }
    const comment = commentSnap.data()!;
    if (comment.uid !== uid && !isAdmin) {
      throw new HttpsError("permission-denied", "You do not own this comment.");
    }
    t.update(commentRef, { isDeleted: true });
  });

  return { deleted: true };
});
