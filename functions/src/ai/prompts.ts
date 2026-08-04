/**
 * Versioned prompt templates — kept out of the callable handler so a prompt
 * change is a diff here, not a hunt through request-handling code, and so
 * `promptVersion` on each stored message stays traceable to exactly this
 * text. Bump `PROMPT_VERSION` on any change to the templates below.
 */
import { GroundingContext } from "./grounding";

export const PROMPT_VERSION = "v1";

const CHARACTER = `You are Shui's tutor for a short educational video the learner just watched. You
are a patient, specific teacher — warm without being saccharine, no emoji unless the
learner uses them first.

Ground rules:
- Keep turns short: 2-4 sentences by default. This is a phone chat sheet over a video,
  not an essay.
- Never fabricate. If the lesson doesn't cover something, say so plainly, then offer
  what the lesson does say. For questions beyond the transcript you may give general
  knowledge, but mark it clearly as outside this lesson.
- If a learner seems discouraged, respond to that before continuing to drill.`;

function formatQuiz(context: GroundingContext): string {
  if (!context.quiz || context.quiz.length === 0) {
    return "No quiz exists for this video.";
  }
  return context.quiz
    .map(
      (q, i) =>
        `${i + 1}. ${q.prompt}\n   Correct answer: ${q.correctAnswerText}\n   Explanation: ${q.explanation}`
    )
    .join("\n");
}

function formatLearnerRecord(context: GroundingContext): string {
  const r = context.learnerRecord;
  const lines: string[] = [];
  if (r.quizAttempts === 0) {
    lines.push("This learner has not attempted the quiz on this video yet.");
  } else {
    lines.push(
      `This learner has attempted this video's quiz ${r.quizAttempts} time(s), best score ` +
        `${Math.round((r.quizBestScore ?? 0) * 100)}%, currently ${r.quizPassed ? "passing" : "not passing"}.`
    );
    if (r.missedQuestionPrompts.length > 0) {
      lines.push(`On their most recent attempt they missed: ${r.missedQuestionPrompts.join("; ")}.`);
    }
  }
  if (r.topicMasteryPercent !== null) {
    lines.push(`Their overall mastery of this topic is ${r.topicMasteryPercent}%.`);
  }
  return lines.join(" ");
}

function transcriptSection(context: GroundingContext): string {
  if (context.video.transcript) {
    return `Transcript:\n${context.video.transcript}`;
  }
  return (
    "No transcript is available for this video — you only have its title and description " +
    "to work from. Say so plainly if a question needs detail the transcript would have " +
    "had; do not guess at what the video said."
  );
}

/** Shared across both modes — the grounding data itself never differs. */
function preamble(context: GroundingContext): string {
  const neighbors = [
    context.topic.previousVideoTitle ? `Previous video in this topic: "${context.topic.previousVideoTitle}".` : null,
    context.topic.nextVideoTitle ? `Next video in this topic: "${context.topic.nextVideoTitle}".` : null,
  ]
    .filter((s): s is string => s !== null)
    .join(" ");

  return `${CHARACTER}

Lesson video: "${context.video.title}"
Description: ${context.video.description}

Topic: "${context.topic.title}" — ${context.topic.description}
${neighbors}

${transcriptSection(context)}

This video's quiz (for your reference, never read verbatim as a substitute for real
teaching):
${formatQuiz(context)}

Learner record: ${formatLearnerRecord(context)}`;
}

/**
 * Streamed text alone can't carry the structured hints the UI needs
 * (suggested-reply chips, a retention verdict) without a second model call
 * — so the model is asked to append one, delimited so the callable can
 * strip it from what's shown/persisted as the visible reply and parse it
 * separately. `parseModelOutput` in this file is the other half of this
 * contract; keep them in sync if the marker or shape ever changes.
 */
const OUTPUT_FORMAT_INSTRUCTION = `
After your reply, on new lines, output exactly this block (the learner never sees it):
<<<META>>>
{"suggestedReplies": ["...", "...", "..."], "retentionAssessment": null}
<<<END_META>>>

- suggestedReplies: 2-3 short (under 8 words each) follow-up questions or replies the
  learner might tap next, relevant to what you just said.
- retentionAssessment: only set this (never null) the turn you just evaluated the
  learner's answer to a specific quiz question in "Quiz me" mode:
  {"questionIds": ["..."], "verdict": "solid" | "shaky" | "missed"}. Every other turn,
  including your opening message, it must be null.`;

export function buildDiscussSystemPrompt(context: GroundingContext): string {
  return `${preamble(context)}

Mode: Discuss. The learner asks questions; you answer, grounded only in this video and
topic. Evaluate meaning over exact wording when they restate something from the lesson.
${OUTPUT_FORMAT_INSTRUCTION}`;
}

export function buildQuizMeSystemPrompt(context: GroundingContext): string {
  return `${preamble(context)}

Mode: Quiz me. You ask; the learner answers in free text — this is a spoken-style oral
check, not multiple choice, and its whole point is testing understanding, not recall of
exact wording.
- Ask exactly one question per turn. Never ask a question and answer it in the same
  turn.
- If the learner has specific missed questions on this video, open by probing one of
  those first — that's what makes this feel like it's paying attention, not generic.
- Evaluate meaning, not wording: a learner who gets the concept right with different
  words is correct.
- When an answer is partly right, name the correct part before the gap. Never simply
  say "wrong."
- After 3-5 exchanges, give a short summary of what looked solid and what to review,
  then stop drilling.
${OUTPUT_FORMAT_INSTRUCTION}`;
}

export interface RetentionAssessment {
  questionIds: string[];
  verdict: "solid" | "shaky" | "missed";
}

export interface ParsedModelOutput {
  visibleText: string;
  suggestedReplies: string[];
  retentionAssessment: RetentionAssessment | null;
}

function isVerdict(value: unknown): value is RetentionAssessment["verdict"] {
  return value === "solid" || value === "shaky" || value === "missed";
}

function parseRetentionAssessment(raw: { questionIds?: unknown; verdict?: unknown } | null | undefined): RetentionAssessment | null {
  if (!raw || !isVerdict(raw.verdict)) {
    return null;
  }
  const questionIds = Array.isArray(raw.questionIds) ? raw.questionIds.filter((s): s is string => typeof s === "string") : [];
  return { questionIds, verdict: raw.verdict };
}

const META_MARKER = "<<<META>>>";
const META_END_MARKER = "<<<END_META>>>";

/** The text actually shown/persisted so far — everything before the marker,
 * or the whole string if the marker (or model) never shows up. Safe to call
 * on a partial, still-streaming string. */
export function extractVisibleText(raw: string): string {
  const idx = raw.indexOf(META_MARKER);
  return (idx === -1 ? raw : raw.slice(0, idx)).trim();
}

/** Called once on the full, final response. Never throws — a malformed or
 * missing meta block degrades to no chips / no retention update rather
 * than failing the whole turn, since the prose itself is still good. */
export function parseModelOutput(raw: string): ParsedModelOutput {
  const visibleText = extractVisibleText(raw);
  const startIdx = raw.indexOf(META_MARKER);
  if (startIdx === -1) {
    return { visibleText, suggestedReplies: [], retentionAssessment: null };
  }
  const endIdx = raw.indexOf(META_END_MARKER, startIdx);
  const jsonSlice = raw.slice(startIdx + META_MARKER.length, endIdx === -1 ? undefined : endIdx).trim();
  try {
    const parsed = JSON.parse(jsonSlice) as {
      suggestedReplies?: unknown;
      retentionAssessment?: { questionIds?: unknown; verdict?: unknown } | null;
    };
    const suggestedReplies = Array.isArray(parsed.suggestedReplies)
      ? parsed.suggestedReplies.filter((s): s is string => typeof s === "string").slice(0, 3)
      : [];
    const retentionAssessment = parseRetentionAssessment(parsed.retentionAssessment);
    return { visibleText, suggestedReplies, retentionAssessment };
  } catch {
    return { visibleText, suggestedReplies: [], retentionAssessment: null };
  }
}

export function buildSystemPrompt(mode: "discuss" | "quizMe", context: GroundingContext): string {
  return mode === "discuss" ? buildDiscussSystemPrompt(context) : buildQuizMeSystemPrompt(context);
}
