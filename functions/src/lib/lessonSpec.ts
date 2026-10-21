import { scriptCharBudget } from "./golpo";
import { GOLPO_VOICES } from "./golpoCapabilities";
import { LessonDuration, LessonOrientation } from "./tiers";

/**
 * "describe": an idea or a detailed brief (onboarding rules, a procedure) —
 * Shui writes the script from it. "script": the learner's own narration,
 * read word-for-word; Shui only adds the title, quiz, and visuals.
 */
export const LESSON_MODES = ["describe", "script"] as const;
export type LessonMode = (typeof LESSON_MODES)[number];

/** Who the lesson is for — shapes tone, structure, and pacing, not facts. */
export const LESSON_PURPOSES = ["personal", "team_training", "classroom", "social_media"] as const;
export type LessonPurpose = (typeof LESSON_PURPOSES)[number];

export const PURPOSE_GUIDANCE: Record<LessonPurpose, string> = {
  personal: "A curious person learning for themselves — friendly, clear, and engaging.",
  team_training:
    "Workplace training or onboarding for a team — clear, procedural, and professional. Use the exact rules, steps, " +
    "and terms given; number the steps; make the do's and don'ts and what to do when something goes wrong unmistakable.",
  classroom: "Students in a class — structured, defines each term before using it, and builds from basics to the main idea.",
  social_media: "A short social-media post — hook in the first sentence, punchy and high-energy, one memorable takeaway.",
};

/** "auto" leaves the pick to AI Art Wisdom, as every lesson did before voices were selectable. */
export const VOICE_CHOICES = ["auto", ...GOLPO_VOICES] as const;
export type VoiceChoice = (typeof VOICE_CHOICES)[number];

/**
 * Everything that makes one rendered lesson a different asset from another
 * on the same text — and so what the shared lesson cache is keyed on.
 */
export interface LessonSpec {
  duration: LessonDuration;
  orientation: LessonOrientation;
  purpose: LessonPurpose;
  voice: VoiceChoice;
}

/**
 * Describe-mode text at or under this length is a short idea: the shared
 * lesson cache exists for exactly these ("how does compound interest work"
 * asked by many people), and the text doubles as the video's title. Longer
 * text is a brief — bespoke, so never cached, and never stored on the video
 * doc, which becomes publicly readable if the lesson is shared to Social.
 */
export const SHORT_IDEA_MAX_CHARS = 300;
export const MAX_BRIEF_CHARS = 5000;
/** What the longest length ("2" minutes) can narrate — the per-length limit is checked against the chosen duration. */
export const MAX_SCRIPT_CHARS = scriptCharBudget("2");
