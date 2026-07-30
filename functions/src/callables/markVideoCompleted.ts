import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { MarkVideoCompletedInputSchema } from "../schemas/callableInputs";
import { DEFAULT_EASE_FACTOR } from "../lib/sm2";
import { computeMasteryPercent, defaultTopicProgressCounters } from "../lib/mastery";

const COMPLETION_THRESHOLD = 0.9;

export const markVideoCompleted = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(MarkVideoCompletedInputSchema, request.data);

  const videoRef = db.collection("videos").doc(input.videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Video not found.");
  }
  const video = videoSnap.data()!;
  const isCompleted =
    video.durationSeconds > 0 && input.watchedSeconds / video.durationSeconds >= COMPLETION_THRESHOLD;

  const topicRef = db.collection("topics").doc(video.topicId);
  const videoProgressRef = db.collection("users").doc(uid).collection("videoProgress").doc(input.videoId);
  const topicProgressRef = db.collection("users").doc(uid).collection("topicProgress").doc(video.topicId);
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (t) => {
    const [topicSnap, videoProgressSnap, topicProgressSnap, userSnap] = await Promise.all([
      t.get(topicRef),
      t.get(videoProgressRef),
      t.get(topicProgressRef),
      t.get(userRef),
    ]);

    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }

    const vp = videoProgressSnap.exists ? videoProgressSnap.data()! : null;
    const wasCompletedBefore = vp?.completed ?? false;
    const justCompleted = isCompleted && !wasCompletedBefore;

    t.set(
      videoProgressRef,
      {
        videoId: input.videoId,
        topicId: video.topicId,
        watchedSeconds: Math.max(vp?.watchedSeconds ?? 0, input.watchedSeconds),
        completed: wasCompletedBefore || isCompleted,
        completedAt: wasCompletedBefore
          ? vp?.completedAt ?? FieldValue.serverTimestamp()
          : isCompleted
          ? FieldValue.serverTimestamp()
          : null,
        quizAttempts: vp?.quizAttempts ?? 0,
        quizBestScore: vp?.quizBestScore ?? 0,
        quizPassed: vp?.quizPassed ?? false,
        lastAnsweredAt: vp?.lastAnsweredAt ?? null,
        easeFactor: vp?.easeFactor ?? DEFAULT_EASE_FACTOR,
        intervalDays: vp?.intervalDays ?? 0,
        repetitions: vp?.repetitions ?? 0,
        dueDate: vp?.dueDate ?? new Date(),
      },
      { merge: true }
    );

    const userUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      lastActiveAt: FieldValue.serverTimestamp(),
    };
    if (justCompleted) {
      t.update(videoRef, { completionCount: FieldValue.increment(1) });
      userUpdate.totalVideosCompleted = FieldValue.increment(1);
    }
    t.update(userRef, userUpdate);

    const tp = topicProgressSnap.exists ? topicProgressSnap.data()! : null;
    const priorCounters = tp
      ? {
          videosCompleted: tp.videosCompleted ?? 0,
          videosTotal: tp.videosTotal ?? 0,
          quizzesAttempted: tp.quizzesAttempted ?? 0,
          quizzesPassed: tp.quizzesPassed ?? 0,
          correctAnswers: tp.correctAnswers ?? 0,
          totalAnswers: tp.totalAnswers ?? 0,
        }
      : defaultTopicProgressCounters();

    const videosTotal = topicSnap.exists
      ? topicSnap.data()!.videoCount ?? priorCounters.videosTotal
      : priorCounters.videosTotal;

    const counters = {
      ...priorCounters,
      videosTotal,
      videosCompleted: justCompleted ? priorCounters.videosCompleted + 1 : priorCounters.videosCompleted,
    };

    t.set(
      topicProgressRef,
      {
        topicId: video.topicId,
        topicTitle: video.topicTitle,
        categoryId: video.categoryId,
        ...counters,
        masteryPercent: computeMasteryPercent(counters),
        startedAt: tp?.startedAt ?? FieldValue.serverTimestamp(),
        lastActivityAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

  return { completed: isCompleted };
});
