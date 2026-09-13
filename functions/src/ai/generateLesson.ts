import { HttpsError } from "firebase-functions/v2/https";
import { CATEGORY_SLUGS, CategorySlug, isCategorySlug } from "../lib/categories";
import { GolpoTiming } from "../lib/tiers";
import { scriptCharBudget } from "../lib/golpo";
import { DEFAULT_GOLPO_SETTINGS, GolpoSettings, GolpoSettingsSchema } from "../lib/golpoCapabilities";
import { buildArtWisdomPromptSection } from "../lib/artWisdom";
import { QuizInputSchema, QuizQuestionInput } from "../schemas/quiz";
import { ModelClient } from "./modelClient";
import { CallUsage } from "./pricing";

const MAX_OUTPUT_TOKENS = 3000;

export interface GeneratedLesson {
  refused: false;
  categoryId: CategorySlug;
  script: string;
  questions: QuizQuestionInput[];
  golpoSettings: GolpoSettings;
}

export interface RefusedLesson {
  refused: true;
  reason: string;
}

/**
 * One Claude call produces script + quiz + category together — the whole
 * point being that Shui never hands GolpoAI a bare topic (its own
 * prompt-expansion is generic, per phase-07 §2's research) and never makes
 * a second call for the quiz. This is the single most load-bearing prompt
 * in the pipeline: the script it writes is exactly what gets rendered and
 * exactly what the quiz is graded against.
 */
function buildPrompt(topic: string, timing: GolpoTiming): string {
  const charBudget = scriptCharBudget(timing);
  return `You write a short educational lesson script, a comprehension quiz, and the
GolpoAI render settings for a short-form vertical video app.

Topic requested: "${topic}"
Target length: ${timing} minute(s) of narration — the script MUST be under ${charBudget}
characters, spoken-style prose, no stage directions or scene markers.

Pick exactly one category for this lesson from this closed list (respond with the slug):
${CATEGORY_SLUGS.join(", ")}

If the topic is unsafe, nonsensical, or not something an educational video can
responsibly and accurately cover, respond with exactly this and nothing else:
{"refused": true, "reason": "<one sentence, shown directly to the learner>"}

Otherwise write 1-5 quiz questions that test whether someone understood THIS SCRIPT's
actual content — not trivia, not wording recall. Each question needs 2-6 options,
exactly one correct, and an explanation that teaches the person who got it wrong.
Never invent facts the script doesn't state.

${buildArtWisdomPromptSection()}

Respond with JSON only — no prose, no markdown fence — matching exactly:
{
  "refused": false,
  "categoryId": "<one slug from the list above>",
  "script": "<the narration, under ${charBudget} characters>",
  "quiz": {
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
  },
  "golpoSettings": {
    "engine": "golpo_canvas | golpo_sketch",
    "canvasStyleVariant": "<required if engine is golpo_canvas, one value from the Canvas list above>",
    "sketchStyleVariant": "<required if engine is golpo_sketch, one value from the Sketch list above>",
    "penAnimationStyle": "<optional, Canvas only>",
    "scenePacing": "normal | fast",
    "voice": "<one value from the voices list above>",
    "musicTrack": "<optional, one value from the music list above, omit for narration-only>",
    "visualInstructions": "<optional but strongly encouraged — what Golpo should actually draw for this script's core claim>",
    "narrationInstructions": "<optional>"
  }
}`;
}

export function parseGeneratedLesson(raw: string, timing: GolpoTiming): GeneratedLesson | RefusedLesson {
  const cleaned = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new HttpsError("internal", "The lesson draft came back in a format we couldn't read. Try again.");
  }

  const obj = parsed as Record<string, unknown>;
  if (obj.refused === true) {
    const reason = typeof obj.reason === "string" && obj.reason.trim() ? obj.reason : "That topic isn't something we can make a lesson for.";
    return { refused: true, reason };
  }

  const categoryId = obj.categoryId;
  const script = obj.script;
  const quiz = obj.quiz as { questions?: unknown } | undefined;

  if (!isCategorySlug(categoryId) || typeof script !== "string" || !script.trim() || !quiz || !Array.isArray(quiz.questions)) {
    throw new HttpsError("internal", "The lesson draft came back incomplete. Try again.");
  }

  const charBudget = scriptCharBudget(timing);
  if (script.length > charBudget) {
    throw new HttpsError(
      "internal",
      `The generated script ran long for a ${timing}-minute lesson. Try again.`
    );
  }

  // Reuse QuizInputSchema's exact validation — a malformed on-demand quiz
  // gets caught here the same way saveQuiz catches a malformed human one.
  // videoId is filled in by the caller once the video doc exists; a
  // placeholder here only exercises option/answer-shape validation.
  const quizResult = QuizInputSchema.safeParse({ videoId: "placeholder", questions: quiz.questions });
  if (!quizResult.success) {
    throw new HttpsError("internal", "The lesson's quiz came back malformed. Try again.");
  }

  // Golpo settings get the gentlest possible failure mode: a malformed or
  // missing style pick falls back to DEFAULT_GOLPO_SETTINGS rather than
  // failing the whole generation — the video still renders, just with the
  // safe generic look instead of one tailored to this topic.
  const golpoSettingsResult = GolpoSettingsSchema.safeParse(obj.golpoSettings);
  const golpoSettings = golpoSettingsResult.success ? golpoSettingsResult.data : DEFAULT_GOLPO_SETTINGS;

  return { refused: false, categoryId, script, questions: quizResult.data.questions, golpoSettings };
}

export interface RunGenerateLessonResult {
  result: GeneratedLesson | RefusedLesson;
  /** The real token usage for this call — callers bill it against the Anthropic provider budget (providerBudgets.ts), refused or not: a refusal still spends tokens. */
  usage: CallUsage;
}

export async function runGenerateLesson(topic: string, timing: GolpoTiming, modelClient: ModelClient): Promise<RunGenerateLessonResult> {
  const { text: raw, usage } = await modelClient.stream({
    system: buildPrompt(topic, timing),
    messages: [{ role: "user", content: `Write the lesson for: ${topic}` }],
    maxTokens: MAX_OUTPUT_TOKENS,
    onToken: () => {},
  });
  return { result: parseGeneratedLesson(raw, timing), usage };
}
