import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { SubmitQuizAttemptInputSchema } from "../schemas/callableInputs";
import { StoredQuizAnswers, StoredQuizCurrent } from "../schemas/quiz";
import { DEFAULT_EASE_FACTOR, ReviewState, newReviewState, schedule } from "../lib/sm2";
import { computeMasteryPercent, defaultTopicProgressCounters } from "../lib/mastery";
import { nextStreak } from "../lib/streak";

export const submitQuizAttempt = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(SubmitQuizAttemptInputSchema, request.data);

  const videoRef = db.collection("videos").doc(input.videoId);
  const currentRef = videoRef.collection("quiz").doc("current");
  const answersRef = videoRef.collection("quiz").doc("answers");

  const [videoSnap, currentSnap, answersSnap] = await Promise.all([
    videoRef.get(),
    currentRef.get(),
    answersRef.get(),
  ]);

  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Video not found.");
  }
  if (!currentSnap.exists || !answersSnap.exists) {
    throw new HttpsError("failed-precondition", "This video has no quiz.");
  }

  const video = videoSnap.data()!;
  const current = currentSnap.data() as StoredQuizCurrent;
  const answerKey = answersSnap.data() as StoredQuizAnswers;
  const answersById = new Map(answerKey.answers.map((a) => [a.id, a]));
  const submittedById = new Map(input.answers.map((a) => [a.questionId, a.selectedOptionIds]));

  const results = current.questions.map((question) => {
    const answer = answersById.get(question.id);
    if (!answer) {
      throw new HttpsError("internal", `Quiz answer key missing for question ${question.id}.`);
    }
    const selected = new Set(submittedById.get(question.id) ?? []);
    const correct = new Set(answer.correctOptionIds);
    const wasCorrect = selected.size === correct.size && [...selected].every((id) => correct.has(id));
    return {
      questionId: question.id,
      wasCorrect,
      correctOptionIds: answer.correctOptionIds,
      explanation: answer.explanation,
    };
  });

  const correctCount = results.filter((r) => r.wasCorrect).length;
  const score = results.length === 0 ? 0 : correctCount / results.length;
  const passed = score >= current.passThreshold;
  const now = new Date();

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

    // ---- videoProgress + SM-2 ----
    const vp = videoProgressSnap.exists ? videoProgressSnap.data()! : null;
    const priorState: ReviewState = vp
      ? {
          easeFactor: vp.easeFactor ?? DEFAULT_EASE_FACTOR,
          intervalDays: vp.intervalDays ?? 0,
          repetitions: vp.repetitions ?? 0,
          dueDate: vp.dueDate?.toDate?.() ?? now,
          lastReviewedAt: vp.lastAnsweredAt?.toDate?.() ?? null,
        }
      : newReviewState(now);
    const nextState = schedule(priorState, passed ? "good" : "again", now);

    const priorAttempts = vp?.quizAttempts ?? 0;
    const priorBestScore = vp?.quizBestScore ?? 0;
    const priorPassed = vp?.quizPassed ?? false;

    t.set(
      videoProgressRef,
      {
        videoId: input.videoId,
        topicId: video.topicId,
        watchedSeconds: vp?.watchedSeconds ?? 0,
        completed: vp?.completed ?? false,
        completedAt: vp?.completedAt ?? null,
        quizAttempts: priorAttempts + 1,
        quizBestScore: Math.max(priorBestScore, score),
        quizPassed: priorPassed || passed,
        lastAnsweredAt: FieldValue.serverTimestamp(),
        easeFactor: nextState.easeFactor,
        intervalDays: nextState.intervalDays,
        repetitions: nextState.repetitions,
        dueDate: nextState.dueDate,
      },
      { merge: true }
    );

    // ---- topicProgress ----
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
      videosCompleted: priorCounters.videosCompleted,
      videosTotal,
      quizzesAttempted: priorCounters.quizzesAttempted + 1,
      quizzesPassed: passed && !priorPassed ? priorCounters.quizzesPassed + 1 : priorCounters.quizzesPassed,
      correctAnswers: priorCounters.correctAnswers + correctCount,
      totalAnswers: priorCounters.totalAnswers + results.length,
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

    // ---- user streak + aggregate counters ----
    const user = userSnap.data()!;
    const { currentStreak, longestStreak } = nextStreak(
      user.lastActiveAt?.toDate?.() ?? null,
      now,
      user.currentStreak ?? 0,
      user.longestStreak ?? 0
    );

    const userUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      lastActiveAt: FieldValue.serverTimestamp(),
      currentStreak,
      longestStreak,
    };
    if (passed && !priorPassed) {
      userUpdate.totalQuizzesPassed = FieldValue.increment(1);
    }
    t.update(userRef, userUpdate);
  });

  return { score, passed, results };
});
