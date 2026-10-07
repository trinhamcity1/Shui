import { HttpsError } from "firebase-functions/v2/https";
import { QuizInputSchema, QuizQuestionInput } from "../schemas/quiz";
import { ModelClient } from "./modelClient";
import { CallUsage } from "./pricing";

const MAX_OUTPUT_TOKENS = 1500;

/**
 * Quiz-only regeneration for an on-demand lesson that already has a saved
 * script — the script itself is never touched (that's what the learner's
 * video actually narrates), only a fresh set of comprehension questions
 * against it. Deliberately a separate, smaller prompt from
 * generateLesson.ts's `buildPrompt` rather than reusing it: that one also
 * writes the script and Golpo settings, neither of which applies here.
 */
function buildPrompt(script: string): string {
  return `You write a comprehension quiz for a short-form educational video. You are
given the exact narration script the video already uses — do not invent new
facts, and do not change the script itself.

Script:
"""
${script}
"""

Write 1-5 quiz questions that test whether someone understood THIS SCRIPT's
actual content — not trivia, not wording recall. Each question needs 2-6
options, exactly one correct, and an explanation that teaches the person who
got it wrong. Never invent facts the script doesn't state. This is a
regeneration request — write a genuinely different set of questions than an
obvious first pass would, not a near-duplicate of the most predictable quiz.

Respond with JSON only — no prose, no markdown fence — matching exactly:
{
  "questions": [
    {
      "id": "q1",
      "prompt": "...",
      "options": [{"id": "a", "text": "..."}, {"id": "b", "text": "..."}],
      "correctOptionIds": ["a"],
      "requiredCorrectCount": 1,
      "explanation": "...",
      "orderIndex": 0
    }
  ]
}`;
}

/**
 * Pure parse/validate — split from `runRegenerateQuiz` the same way
 * generateLesson.ts separates `parseGeneratedLesson` from
 * `runGenerateLesson`, so it's unit-testable without a model client.
 */
export function parseRegeneratedQuiz(raw: string): QuizQuestionInput[] {
  const cleaned = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new HttpsError("internal", "The regenerated quiz came back in a format we couldn't read. Try again.");
  }

  const obj = parsed as { questions?: unknown };
  if (!Array.isArray(obj.questions)) {
    throw new HttpsError("internal", "The regenerated quiz came back incomplete. Try again.");
  }

  // Reuse QuizInputSchema's exact validation — same discipline as
  // generateLesson.ts's parseGeneratedLesson. videoId is a placeholder; the
  // real id is filled in by the caller when it actually saves this.
  const quizResult = QuizInputSchema.safeParse({ videoId: "placeholder", questions: obj.questions });
  if (!quizResult.success) {
    throw new HttpsError("internal", "The regenerated quiz came back malformed. Try again.");
  }

  return quizResult.data.questions;
}

export interface RunRegenerateQuizResult {
  questions: QuizQuestionInput[];
  usage: CallUsage;
}

export async function runRegenerateQuiz(script: string, modelClient: ModelClient): Promise<RunRegenerateQuizResult> {
  const { text: raw, usage } = await modelClient.stream({
    system: buildPrompt(script),
    messages: [{ role: "user", content: "Write the quiz." }],
    maxTokens: MAX_OUTPUT_TOKENS,
    onToken: () => {},
  });
  return { questions: parseRegeneratedQuiz(raw), usage };
}
