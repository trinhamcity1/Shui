import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { AiTutorMessageInput, AiTutorMessageInputSchema } from "../schemas/callableInputs";
import { assembleGroundingContext } from "../ai/grounding";
import { buildSystemPrompt, extractVisibleText, parseModelOutput, PROMPT_VERSION, RetentionAssessment } from "../ai/prompts";
import { AI_SECRETS, AnthropicModelClient, ModelClient, ModelMessage } from "../ai/modelClient";
import { checkAndRecordUsage } from "../ai/rateLimit";
import { DEFAULT_EASE_FACTOR, newReviewState, ReviewState, schedule } from "../lib/sm2";

// A short-turn tutor, not an essay generator — the prompt already
// constrains length in words; this is just a hard cost ceiling behind it.
const MAX_OUTPUT_TOKENS = 500;
const FLUSH_INTERVAL_MS = 200;

export interface AiTutorMessageResult {
  messageId: string;
  text: string;
  suggestedReplies: string[];
  retentionAssessment: RetentionAssessment | null;
}

function canReadVideo(video: FirebaseFirestore.DocumentData, uid: string): boolean {
  const isPublic =
    video.status === "ready" && video.visibility === "public" && video.topicVisibility === "public" && !video.isDeleted;
  return isPublic || video.createdBy === uid;
}

/**
 * The real work, factored out from the `onCall` wrapper below so evals and
 * unit tests can call it directly with a `FakeModelClient` — no HTTP layer,
 * no auth emulation, and no real API key needed to exercise grounding,
 * prompting, and response-parsing logic.
 */
export async function runAiTutorMessage(
  uid: string,
  input: AiTutorMessageInput,
  modelClient: ModelClient
): Promise<AiTutorMessageResult> {
  const videoRef = db.collection("videos").doc(input.videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Video not found.");
  }
  if (!canReadVideo(videoSnap.data()!, uid)) {
    throw new HttpsError("permission-denied", "You cannot access this video.");
  }

  const usage = await checkAndRecordUsage(uid);
  if (!usage.allowed) {
    throw new HttpsError("resource-exhausted", "You've reached the AI tutor's usage limit for now.", {
      resetAt: usage.resetAt.toISOString(),
    });
  }

  const context = await assembleGroundingContext({ uid, videoId: input.videoId });
  if (!context) {
    throw new HttpsError("not-found", "Video not found.");
  }

  const threadRef = videoRef.collection("aiThreads").doc(uid);
  const messagesRef = threadRef.collection("messages");
  const serverNow = FieldValue.serverTimestamp();

  if (!input.isSessionStart) {
    await messagesRef.add({ role: "user", mode: input.mode, text: input.text, createdAt: serverNow, updatedAt: serverNow });
  }

  const assistantRef = messagesRef.doc();
  await assistantRef.set({
    role: "assistant",
    mode: input.mode,
    text: "",
    status: "streaming",
    suggestedReplies: [],
    retentionAssessment: null,
    promptVersion: PROMPT_VERSION,
    createdAt: serverNow,
    updatedAt: serverNow,
  });

  const systemPrompt = buildSystemPrompt(input.mode, context);
  const modelMessages: ModelMessage[] = context.recentMessages.map((m) => ({ role: m.role, content: m.content }));
  modelMessages.push({
    role: "user",
    content: input.isSessionStart
      ? input.mode === "discuss"
        ? "The learner just opened this video. Give a one-sentence welcome inviting questions about it."
        : "The learner just opened Quiz me. Begin by asking your first question — if they have specific missed " +
          "questions on this video, probe one of those first."
      : input.text!,
  });

  let accumulated = "";
  let lastFlushAt = 0;
  let lastFlushedVisible = "";
  const rawResult = await modelClient.stream({
    system: systemPrompt,
    messages: modelMessages,
    maxTokens: MAX_OUTPUT_TOKENS,
    onToken: async (delta) => {
      accumulated += delta;
      const now = Date.now();
      if (now - lastFlushAt < FLUSH_INTERVAL_MS) return;
      lastFlushAt = now;
      const visible = extractVisibleText(accumulated);
      if (visible === lastFlushedVisible) return;
      lastFlushedVisible = visible;
      await assistantRef.update({ text: visible, updatedAt: FieldValue.serverTimestamp() });
    },
  });

  const { visibleText, suggestedReplies, retentionAssessment } = parseModelOutput(rawResult);
  await applyRetentionAssessment(uid, input.videoId, retentionAssessment);

  await assistantRef.update({
    text: visibleText,
    status: "complete",
    suggestedReplies,
    retentionAssessment,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await threadRef.set({ updatedAt: FieldValue.serverTimestamp(), lastMode: input.mode }, { merge: true });

  return { messageId: assistantRef.id, text: visibleText, suggestedReplies, retentionAssessment };
}

/**
 * A conversational miss in "Quiz me" pulls the video forward in the review
 * queue exactly as a failed multiple-choice question does — same SM-2 code
 * path submitQuizAttempt uses, not a second scheduler.
 */
async function applyRetentionAssessment(
  uid: string,
  videoId: string,
  assessment: RetentionAssessment | null
): Promise<void> {
  if (!assessment || assessment.verdict === "solid") return;
  const grade = assessment.verdict === "missed" ? "again" : "hard";
  const videoProgressRef = db.collection("users").doc(uid).collection("videoProgress").doc(videoId);

  await db.runTransaction(async (t) => {
    const snap = await t.get(videoProgressRef);
    const vp = snap.exists ? snap.data()! : null;
    const now = new Date();
    const priorState: ReviewState = vp
      ? {
          easeFactor: vp.easeFactor ?? DEFAULT_EASE_FACTOR,
          intervalDays: vp.intervalDays ?? 0,
          repetitions: vp.repetitions ?? 0,
          dueDate: vp.dueDate?.toDate?.() ?? now,
          lastReviewedAt: vp.lastAnsweredAt?.toDate?.() ?? null,
        }
      : newReviewState(now);
    const nextState = schedule(priorState, grade, now);
    t.set(
      videoProgressRef,
      {
        videoId,
        easeFactor: nextState.easeFactor,
        intervalDays: nextState.intervalDays,
        repetitions: nextState.repetitions,
        dueDate: nextState.dueDate,
      },
      { merge: true }
    );
  });
}

export const aiTutorMessage = onCall({ secrets: AI_SECRETS, timeoutSeconds: 120 }, async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(AiTutorMessageInputSchema, request.data);
  return runAiTutorMessage(uid, input, new AnthropicModelClient());
});
