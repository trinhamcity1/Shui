import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ShareLessonToSocialInputSchema } from "../schemas/callableInputs";
import { splitQuizForStorage } from "../schemas/quiz";
import { runRegenerateQuiz } from "../ai/regenerateQuiz";
import { AnthropicModelClient, AI_SECRETS } from "../ai/modelClient";
import { dateKey } from "../lib/dailyUsageStats";

/** Per video, per UTC day — resets at midnight UTC, same boundary `dateKey` uses everywhere else in this codebase. */
export const DAILY_QUIZ_REGEN_LIMIT = 3;

/**
 * Self-serve quiz regeneration for the owner of an on-demand lesson — not
 * gated to creator/admin the way suggestQuizQuestions.ts is, since this is
 * a learner's own generated lesson, not curated content. Re-runs Claude
 * against the already-saved script only (never touches the script or the
 * rendered video) and overwrites the saved quiz outright, unlike
 * suggestQuizQuestions.ts's draft-for-review-before-saving flow — there's
 * no separate "save" step here by design, matching how the lesson's quiz
 * was written the first time (createOnDemandLesson.ts never asks for
 * confirmation either).
 */
export const regenerateOnDemandLessonQuiz = onCall({ secrets: AI_SECRETS }, async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(ShareLessonToSocialInputSchema, request.data);

  const videoRef = db.collection("videos").doc(input.videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Lesson not found.");
  }
  const video = videoSnap.data()!;
  if (video.createdBy !== uid) {
    throw new HttpsError("permission-denied", "This is not your lesson.");
  }
  if (video.generationSource !== "on_demand") {
    throw new HttpsError("failed-precondition", "Only an on-demand lesson's quiz can be regenerated this way.");
  }
  const script = video.transcript as string | undefined;
  if (!script || !script.trim()) {
    throw new HttpsError("failed-precondition", "This lesson has no script to regenerate a quiz from.");
  }

  const today = dateKey(new Date());
  const countToday = video.quizRegenDateKey === today ? (video.quizRegenCount as number | undefined) ?? 0 : 0;
  if (countToday >= DAILY_QUIZ_REGEN_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      `You've used today's ${DAILY_QUIZ_REGEN_LIMIT} quiz regenerations for this lesson — resets at midnight UTC.`
    );
  }

  // A real Claude call, outside any transaction — never hold a Firestore
  // transaction open across a slow network round trip. Free to the learner
  // (no wallet debit, no AI-tutor-cap interaction — this isn't that budget)
  // — the daily limit below is the actual cost control, not a charge.
  const { questions } = await runRegenerateQuiz(script, new AnthropicModelClient());

  const quizRef = videoRef.collection("quiz").doc("current");
  const answersRef = videoRef.collection("quiz").doc("answers");

  const remaining = await db.runTransaction(async (t) => {
    const [freshVideoSnap, currentSnap] = await Promise.all([t.get(videoRef), t.get(quizRef)]);
    const freshVideo = freshVideoSnap.data()!;
    // Re-check the limit against the latest doc — closes the gap a slow
    // Claude call leaves open for a rapid double-tap to slip two requests
    // past the earlier, now-stale read.
    const freshCount = freshVideo.quizRegenDateKey === today ? (freshVideo.quizRegenCount as number | undefined) ?? 0 : 0;
    if (freshCount >= DAILY_QUIZ_REGEN_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        `You've used today's ${DAILY_QUIZ_REGEN_LIMIT} quiz regenerations for this lesson — resets at midnight UTC.`
      );
    }

    const nextVersion = currentSnap.exists ? (currentSnap.data()!.version ?? 0) + 1 : 1;
    const { current, answers } = splitQuizForStorage(
      { videoId: input.videoId, questions, passThreshold: currentSnap.data()?.passThreshold ?? 0.6 },
      nextVersion,
      uid,
      FieldValue.serverTimestamp()
    );
    t.set(quizRef, current);
    t.set(answersRef, answers);
    t.update(videoRef, {
      hasQuiz: true,
      quizRegenCount: freshCount + 1,
      quizRegenDateKey: today,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return DAILY_QUIZ_REGEN_LIMIT - (freshCount + 1);
  });

  return { questions, remainingToday: remaining };
});
