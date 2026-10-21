import { onCall, HttpsError } from "firebase-functions/v2/https";
import { randomUUID } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateOnDemandLessonInputSchema } from "../schemas/callableInputs";
import { debitForLesson, refundLesson } from "../lib/credits";
import { durationLabel, golpoTimingFor, LessonDuration, LessonOrientation, tierOf } from "../lib/tiers";
import { LessonMode, LessonPurpose, LessonSpec, SHORT_IDEA_MAX_CHARS } from "../lib/lessonSpec";
import { GolpoVoice } from "../lib/golpoCapabilities";
import { lookupLessonCache, recordLessonCacheHit } from "../lib/lessonCache";
import { runGenerateLesson } from "../ai/generateLesson";
import { splitQuizForStorage, QuizInputSchema } from "../schemas/quiz";
import { AnthropicModelClient, ModelClient, AI_SECRETS } from "../ai/modelClient";
import { GolpoClient, GolpoRestClient, GOLPO_SECRETS, scriptCharBudget } from "../lib/golpo";
import { baseOnDemandVideoShape, ensurePersonalTopic, truncateTitle } from "../lib/onDemandVideo";
import { ALERT_SECRETS, checkProvidersAvailable } from "../lib/providerBudgets";

/** Shown to the learner when Shui's own Golpo/Anthropic account is genuinely out of tracked credit — a distinct HttpsError code ("unavailable") so the app can show a dedicated "tools offline" screen instead of the generic failed-with-retry UI. */
export const PROVIDERS_UNAVAILABLE_MESSAGE = "Lesson creation is temporarily offline for maintenance. Please check back soon.";

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

/** What a learner (or developer-API caller) asks for — every field but the text is optional. */
export interface CreateLessonRequest {
  /** Defaults to "describe". */
  mode?: LessonMode;
  /** Describe mode: an idea or a detailed brief. */
  topic?: string;
  /** Script mode: the narration, read word-for-word. */
  script?: string;
  duration?: LessonDuration;
  orientation?: LessonOrientation;
  purpose?: LessonPurpose;
  /** Omitted means AI Art Wisdom picks the voice. */
  voice?: GolpoVoice;
}

/**
 * The real work, factored out from the `onCall` wrapper so tests can supply
 * `FakeModelClient`/`FakeGolpoClient` — same split as every other AI-backed
 * callable in this codebase (suggestQuizQuestions, aiTutorMessage).
 */
export async function runCreateOnDemandLesson(
  uid: string,
  request: CreateLessonRequest,
  deps: { modelClient: ModelClient; golpoClient: GolpoClient },
  // true only for requests through the developer API (functions/src/api/lessonsApi.ts) —
  // the app callable at the bottom of this file always leaves this at its
  // default. Drives the Social feed's `originatedFromApi == false` filter
  // (phase-07 §6/§8): API-generated content is cache-eligible but never
  // Social-eligible.
  originatedFromApi = false
): Promise<CreateOnDemandLessonResult> {
  const mode: LessonMode = request.mode ?? "describe";
  const text = ((mode === "script" ? request.script : request.topic) ?? "").trim();
  if (!text) {
    throw new HttpsError("invalid-argument", mode === "script" ? "Write a script first." : "Describe what you want to learn first.");
  }
  // Checked before anything is charged. The app blocks this already; this is
  // the real gate, and the schema guarantees `duration` in script mode.
  if (mode === "script" && request.duration && text.length > scriptCharBudget(request.duration)) {
    throw new HttpsError(
      "invalid-argument",
      `Your script is ${text.length} characters — a ${durationLabel(request.duration)} lesson fits up to ` +
        `${scriptCharBudget(request.duration)}. Shorten it or pick a longer length.`
    );
  }
  const isShortIdea = mode === "describe" && text.length <= SHORT_IDEA_MAX_CHARS;

  // The circuit breaker — checked before anything is debited or spent, so a
  // learner is never charged for a lesson Shui's own account can't actually
  // afford to render. See providerBudgets.ts's own doc comment for why this
  // is a blunt exhausted/not-exhausted check, not a per-request estimate.
  const availability = await checkProvidersAvailable();
  if (!availability.available) {
    throw new HttpsError("unavailable", PROVIDERS_UNAVAILABLE_MESSAGE);
  }

  const topicId = await ensurePersonalTopic(uid);

  // The debit comes first because it's what resolves (and tier-checks) the
  // duration everything below is keyed on.
  const debit = await debitForLesson(uid, request.duration);
  const tier = tierOf(debit.tier);
  const spec: LessonSpec = {
    duration: debit.duration,
    orientation: request.orientation ?? "vertical",
    purpose: request.purpose ?? "personal",
    voice: request.voice ?? "auto",
  };

  // Cache hit: skip Claude and GolpoAI entirely (phase-07 §5) — short ideas
  // only; a brief or a learner's own script is bespoke. A cache hit is pure
  // margin, not a discount: the debit above still stands.
  const cached = isShortIdea ? await lookupLessonCache(text, spec) : null;
  if (cached) {
    const sourceSnap = await db.collection("videos").doc(cached.sourceVideoId).get();
    const source = sourceSnap.data();
    if (source && !source.isDeleted) {
      const videoId = randomUUID();
      await db
        .collection("videos")
        .doc(videoId)
        .set({
          ...baseOnDemandVideoShape({ uid, topicId, categoryId: cached.categoryId, title: truncateTitle(text) }),
          ...lessonShapeFields(mode, text, isShortIdea, spec),
          status: "ready",
          transcript: source.transcript ?? null,
          transcriptSource: "on_demand_script",
          playbackURL: source.playbackURL ?? null,
          watermarkedPlaybackURL: source.watermarkedPlaybackURL ?? null,
          durationSeconds: source.durationSeconds ?? null,
          sizeBytes: source.sizeBytes ?? null,
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
      await recordLessonCacheHit(text, spec);
      return { videoId, status: "ready" };
    }
    // Cached source no longer exists/was deleted — fall through to a real generation.
  }

  const { result: generated } = await runGenerateLesson({ mode, text }, spec, deps.modelClient);

  if (generated.refused) {
    await refundLesson(uid, debit.debitedCents, null);
    throw new HttpsError("invalid-argument", generated.reason);
  }

  // A short idea is its own title, as it always was; a brief or a script
  // needs a real one rather than its first 80 characters.
  const title = truncateTitle(isShortIdea ? text : generated.title ?? text);
  const golpoSettings = spec.voice === "auto" ? generated.golpoSettings : { ...generated.golpoSettings, voice: spec.voice };

  const videoId = randomUUID();
  const golpo = await deps.golpoClient.generate({
    topic: title,
    customScript: generated.script,
    timing: golpoTimingFor(spec.duration),
    orientation: spec.orientation,
    settings: golpoSettings,
  });
  // No self-tracked spend recording for Golpo anymore — GolpoAI's own
  // /users/credits balance already reflects this the instant their API
  // applies it (providerBudgets.ts's getGolpoRemainingCentsLive reads it
  // live, cached), so a second, separately-tracked figure would only drift.

  await db
    .collection("videos")
    .doc(videoId)
    .set({
      ...baseOnDemandVideoShape({ uid, topicId, categoryId: generated.categoryId, title }),
      ...lessonShapeFields(mode, text, isShortIdea, spec),
      status: "generating",
      transcript: generated.script,
      transcriptSource: "on_demand_script",
      playbackURL: null,
      watermarkedPlaybackURL: null,
      durationSeconds: null,
      sizeBytes: null,
      generationSource: "on_demand",
      originatedFromApi,
      generatedFromCache: false,
      cacheSourceVideoId: null,
      tierAtGeneration: tier.id,
      costChargedCents: debit.debitedCents,
      hasQuiz: true,
      golpoJobId: golpo.jobId,
      golpoSettings,
    });

  // Written now, not when the render finishes — the quiz is a pure function
  // of the script, and never depends on GolpoAI.
  await writeQuiz(videoId, generated.questions, uid);

  return { videoId, status: "generating" };
}

/**
 * The fields that record how a lesson was asked for. `rawTopic` is kept
 * only for a short idea: it's what the cache write in
 * checkOnDemandLessonStatus keys on (so null also means "never cache"), and
 * a video doc becomes publicly readable once shared to Social — a pasted
 * brief can hold far more than the narration that ends up public anyway.
 */
function lessonShapeFields(mode: LessonMode, text: string, isShortIdea: boolean, spec: LessonSpec) {
  return {
    rawTopic: isShortIdea ? text : null,
    creationMode: mode,
    // The learner's chosen length in minutes ("1.5" included) — not the
    // Golpo `timing` bucket it rendered with (golpoTimingFor).
    timing: spec.duration,
    orientation: spec.orientation,
    purpose: spec.purpose,
    voiceChoice: spec.voice,
  };
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

export const createOnDemandLesson = onCall({ secrets: [...AI_SECRETS, ...GOLPO_SECRETS, ...ALERT_SECRETS] }, async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(CreateOnDemandLessonInputSchema, request.data);
  return runCreateOnDemandLesson(uid, input, {
    modelClient: new AnthropicModelClient(),
    golpoClient: new GolpoRestClient(),
  });
});
