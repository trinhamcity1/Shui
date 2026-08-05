import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db } from "../lib/admin";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { SuggestQuizQuestionsInputSchema } from "../schemas/callableInputs";
import { AnthropicModelClient, AI_SECRETS, ModelClient } from "../ai/modelClient";

const MAX_OUTPUT_TOKENS = 2000;
const TRANSCRIPT_CHAR_BUDGET = 12000;

export interface SuggestedQuestion {
  prompt: string;
  options: Array<{ text: string; isCorrect: boolean }>;
  explanation: string;
}

/**
 * Unlike the tutor's streamed replies — where structured hints have to ride
 * alongside prose in a delimited block the model sometimes forgets (see
 * `functions/src/ai/evals/README.md`) — a quiz draft has no prose half. The
 * entire response is the JSON, so it can be demanded directly and parsed
 * strictly, with no marker to miss. Same reason there's no streaming here:
 * nothing renders until the whole draft is ready anyway.
 */
function buildPrompt(count: number): string {
  return `You write multiple-choice comprehension questions for short educational videos.

Given the lesson below, write exactly ${count} question(s) that test whether someone
understood the video's actual content — not trivia, not wording recall.

Rules:
- Each question gets 3-4 options, exactly one of them correct.
- Wrong options must be plausible to someone who half-watched, never absurd filler.
- Every question needs an explanation of why the correct answer is right, written to
  teach the person who got it wrong. This is the part learners actually read.
- Ask only about what the lesson genuinely covers. Never invent facts it didn't state.

Respond with JSON only — no prose, no markdown fence — matching exactly:
{"questions":[{"prompt":"...","options":[{"text":"...","isCorrect":true},{"text":"...","isCorrect":false}],"explanation":"..."}]}`;
}

export function parseSuggestions(raw: string, expected: number): SuggestedQuestion[] {
  // Models sometimes wrap JSON in a fence despite being told not to; strip
  // it rather than failing the creator's request over formatting.
  const cleaned = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new HttpsError("internal", "The draft came back in a format we couldn't read. Try again.");
  }

  const questions = (parsed as { questions?: unknown }).questions;
  if (!Array.isArray(questions) || questions.length === 0) {
    throw new HttpsError("internal", "The draft came back empty. Try again.");
  }

  const result: SuggestedQuestion[] = [];
  for (const q of questions.slice(0, expected)) {
    const prompt = (q as { prompt?: unknown }).prompt;
    const explanation = (q as { explanation?: unknown }).explanation;
    const options = (q as { options?: unknown }).options;
    if (typeof prompt !== "string" || typeof explanation !== "string" || !Array.isArray(options)) {
      continue;
    }
    const parsedOptions = options
      .filter((o): o is { text: string; isCorrect?: unknown } => typeof (o as { text?: unknown })?.text === "string")
      .map((o) => ({ text: o.text, isCorrect: o.isCorrect === true }));

    // Drop anything that couldn't be saved anyway — the quiz builder's own
    // validation mirrors saveQuiz exactly, and handing a creator a draft
    // that fails validation the moment they open it is worse than handing
    // them one fewer question.
    if (parsedOptions.length < 2 || parsedOptions.length > 6) continue;
    if (parsedOptions.filter((o) => o.isCorrect).length !== 1) continue;
    result.push({ prompt, options: parsedOptions, explanation });
  }

  if (result.length === 0) {
    throw new HttpsError("internal", "The draft didn't produce any usable questions. Try again.");
  }
  return result;
}

export async function runSuggestQuizQuestions(
  uid: string,
  isAdmin: boolean,
  input: { videoId: string; count: number },
  modelClient: ModelClient
): Promise<{ questions: SuggestedQuestion[] }> {
  const videoSnap = await db.collection("videos").doc(input.videoId).get();
  if (!videoSnap.exists) {
    throw new HttpsError("not-found", "Video not found.");
  }
  const video = videoSnap.data()!;
  if (video.createdBy !== uid && !isAdmin) {
    throw new HttpsError("permission-denied", "You do not own this video.");
  }

  const transcript = (video.transcript as string | undefined)?.trim();
  if (!transcript) {
    // Refusing beats drafting from a title alone: a plausible-looking quiz
    // generated from nothing is the easiest way to ship a wrong one, and
    // the creator can't tell by looking.
    throw new HttpsError(
      "failed-precondition",
      "This video has no transcript yet — add one and the draft will be based on what the video actually says."
    );
  }

  const lesson = [
    `Title: ${video.title}`,
    video.description ? `Description: ${video.description}` : null,
    `Transcript:\n${transcript.slice(0, TRANSCRIPT_CHAR_BUDGET)}`,
  ]
    .filter(Boolean)
    .join("\n\n");

  const raw = await modelClient.stream({
    system: buildPrompt(input.count),
    messages: [{ role: "user", content: lesson }],
    maxTokens: MAX_OUTPUT_TOKENS,
    onToken: () => {},
  });

  return { questions: parseSuggestions(raw, input.count) };
}

export const suggestQuizQuestions = onCall({ secrets: AI_SECRETS, timeoutSeconds: 120 }, async (request) => {
  const uid = requireRole(request, ["creator", "admin"]);
  const input = parseInput(SuggestQuizQuestionsInputSchema, request.data);
  return runSuggestQuizQuestions(uid, request.auth!.token.role === "admin", input, new AnthropicModelClient());
});
