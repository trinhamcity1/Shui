import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { SetTopicVisibilityInputSchema, SetVideoVisibilityInputSchema } from "../schemas/callableInputs";

export const setTopicVisibility = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SetTopicVisibilityInputSchema, request.data);
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

    if (input.visibility === "public") {
      const hasReadyVideo = videosSnap.docs.some(
        (d) => d.data().status === "ready" && d.data().isDeleted === false
      );
      if (!hasReadyVideo) {
        throw new HttpsError(
          "failed-precondition",
          "This topic has no ready videos yet — finish uploading at least one video before publishing."
        );
      }
    }

    const wasAlreadyPublic = topic.visibility === "public";
    const nowPublishing = input.visibility === "public" && !wasAlreadyPublic;

    t.update(topicRef, {
      visibility: input.visibility,
      publishedAt: nowPublishing ? FieldValue.serverTimestamp() : topic.publishedAt ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const videoDoc of videosSnap.docs) {
      t.update(videoDoc.ref, { topicVisibility: input.visibility, updatedAt: FieldValue.serverTimestamp() });
    }
  });

  return { visibility: input.visibility };
});

export const setVideoVisibility = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SetVideoVisibilityInputSchema, request.data);
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

    if (input.visibility === "public") {
      if (video.status !== "ready") {
        throw new HttpsError("failed-precondition", "Only a ready video can be published.");
      }
      if (!video.hasQuiz) {
        throw new HttpsError("failed-precondition", "Add a quiz before publishing this video.");
      }
    }

    const wasAlreadyPublic = video.visibility === "public";
    const nowPublishing = input.visibility === "public" && !wasAlreadyPublic;

    t.update(videoRef, {
      visibility: input.visibility,
      publishedAt: nowPublishing ? FieldValue.serverTimestamp() : video.publishedAt ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { visibility: input.visibility };
});
