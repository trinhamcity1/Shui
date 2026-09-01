import { onCall, HttpsError } from "firebase-functions/v2/https";
import { randomUUID } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateOnDemandLessonInputSchema } from "../schemas/callableInputs";
import { debitForLesson, refundLesson } from "../lib/credits";
import { tierOf } from "../lib/tiers";
import { lookupLessonCache, recordLessonCacheHit } from "../lib/lessonCache";
import { runGenerateLesson } from "../ai/generateLesson";
import { splitQuizForStorage, QuizInputSchema } from "../schemas/quiz";
import { AnthropicModelClient, ModelClient, AI_SECRETS } from "../ai/modelClient";
import { GolpoClient, GolpoRestClient, GOLPO_SECRETS } from "../lib/golpo";
import { baseOnDemandVideoShape, ensurePersonalTopic, truncateTitle } from "../lib/onDemandVideo";

export interface CreateOnDemandLessonResult {
  videoId: string;
  status: "generating" | "ready";
}

async function writeQuiz(videoId: string, questions: unknown, updatedBy: string) {
  const parsed = QuizInputSchema.parse({ videoId, questions });
  const { current, answers } = splitQuizForStorage(parsed, 1, updatedBy, FieldValue.serverTimestamp());
  const videoRef = db.collection("videos").doc(videoId);
  await Promise.all([
    videoRef.collection("quiz").doc("current").set(current),
    videoRef.collection("quiz").doc("answers").set(answers),
  ]);
}

/**
 * The real work, factored out from the `onCall` wrapper so tests can supply
 * `FakeModelClient`/`FakeGolpoClient` — same split as every other AI-backed
 * callable in this codebase (suggestQuizQuestions, aiTutorMessage).
 */
export async function runCreateOnDemandLesson(
  uid: string,
  topic: string,
  deps: { modelClient: ModelClient; golpoClient: GolpoClient },
  // true only for requests through the developer API (functions/src/api/lessonsApi.ts) —
  // the app callable at the bottom of this file always leaves this at its
  // default. Drives the Social feed's `originatedFromApi == false` filter
  // (phase-07 §6/§8): API-generated content is cache-eligible but never
  // Social-eligible.
  originatedFromApi = false
): Promise<CreateOnDemandLessonResult> {
  const topicId = await ensurePersonalTopic(uid);

  // Cache hit: skip Claude and GolpoAI entirely (phase-07 §5). The debit
  // still happens — a cache hit is pure margin, not a discount — but the
  // *tier being debited* is looked up first so we know which `timing`
  // bucket to check the cache against.
  const debit = await debitForLesson(uid);
  const tier = tierOf(debit.tier);

  const cached = await lookupLessonCache(topic, debit.timing);
  if (cached) {
    const sourceSnap = await db.collection("videos").doc(cached.sourceVideoId).get();
    const source = sourceSnap.data();
    if (source && !source.isDeleted) {
      const videoId = randomUUID();
      await db
        .collection("videos")
        .doc(videoId)
        .set({
          ...baseOnDemandVideoShape({ uid, topicId, categoryId: cached.categoryId, title: truncateTitle(topic) }),
          rawTopic: topic,
          status: "ready",
          transcript: source.transcript ?? null,
          transcriptSource: "on_demand_script",
          playbackURL: source.playbackURL ?? null,
          watermarkedPlaybackURL: source.watermarkedPlaybackURL ?? null,
          durationSeconds: source.durationSeconds ?? null,
          sizeBytes: source.sizeBytes ?? null,
          timing: debit.timing,
          generationSource: "on_demand",
          originatedFromApi,
          generatedFromCache: true,
          cacheSourceVideoId: cached.sourceVideoId,
          tierAtGeneration: tier.id,
          costChargedCents: debit.debitedCents,
          hasQuiz: true,
          publishedAt: FieldValue.serverTimestamp(),
        });
      await copyQuizFrom(cached.sourceVideoId, videoId);
      await recordLessonCacheHit(topic, debit.timing);
      return { videoId, status: "ready" };
    }
    // Cached source no longer exists/was deleted — fall through to a real generation.
  }

  const generated = await runGenerateLesson(topic, debit.timing, deps.modelClient);
  if (generated.refused) {
    await refundLesson(uid, debit.debitedCents, null);
    throw new HttpsError("invalid-argument", generated.reason);
  }

  const videoId = randomUUID();
  const golpo = await deps.golpoClient.generate({ customScript: generated.script, timing: debit.timing });

  await db
    .collection("videos")
    .doc(videoId)
    .set({
      ...baseOnDemandVideoShape({ uid, topicId, categoryId: generated.categoryId, title: truncateTitle(topic) }),
      status: "generating",
      transcript: generated.script,
      transcriptSource: "on_demand_script",
      playbackURL: null,
      watermarkedPlaybackURL: null,
      durationSeconds: null,
      sizeBytes: null,
      timing: debit.timing,
      generationSource: "on_demand",
      originatedFromApi,
      generatedFromCache: false,
      cacheSourceVideoId: null,
      tierAtGeneration: tier.id,
      costChargedCents: debit.debitedCents,
      hasQuiz: true,
      golpoJobId: golpo.jobId,
    });

  // Written now, not when the render finishes — the quiz is a pure function
  // of the script Claude already returned, and never depends on GolpoAI.
  await writeQuiz(videoId, generated.questions, uid);

  return { videoId, status: "generating" };
}

async function copyQuizFrom(sourceVideoId: string, targetVideoId: string): Promise<void> {
  const sourceRef = db.collection("videos").doc(sourceVideoId);
  const [currentSnap, answersSnap] = await Promise.all([
    sourceRef.collection("quiz").doc("current").get(),
    sourceRef.collection("quiz").doc("answers").get(),
  ]);
  if (!currentSnap.exists || !answersSnap.exists) return;
  const targetRef = db.collection("videos").doc(targetVideoId);
  await Promise.all([
    targetRef.collection("quiz").doc("current").set(currentSnap.data()!),
    targetRef.collection("quiz").doc("answers").set(answersSnap.data()!),
  ]);
}

export const createOnDemandLesson = onCall({ secrets: [...AI_SECRETS, ...GOLPO_SECRETS] }, async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(CreateOnDemandLessonInputSchema, request.data);
  return runCreateOnDemandLesson(uid, input.topic, {
    modelClient: new AnthropicModelClient(),
    golpoClient: new GolpoRestClient(),
  });
});
