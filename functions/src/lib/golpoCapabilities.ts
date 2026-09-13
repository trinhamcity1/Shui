import { z } from "zod";

/**
 * GolpoAI's real v2 capability surface — every engine/style/voice/music
 * value it actually accepts, sourced from video.golpoai.com/api-docs/
 * endpoints/v2 and the style guide at video.golpoai.com/guide/
 * every-golpo-video-style (2026-09). Golpo's own docs describe *what* each
 * style looks like but never *when* to reach for one — the `label`/
 * `description`/`bestFor` text below is Shui's own curated judgment call,
 * not something Golpo publishes. Treat it as a first-pass, reasoned opinion
 * to sharpen with real output once lessons are actually rendering, not a
 * validated-by-research fact.
 *
 * IMPORTANT — verify against the live API dashboard once a real key exists:
 * two of Golpo's own doc pages disagree on the exact voice identifiers
 * ("solo-female-3" vs "female-1" naming). This file follows the structured
 * v2 endpoint reference (the more authoritative of the two), but a 401/422
 * on `narration_voice` at runtime means this needs a one-line correction
 * here — nowhere else, since every caller reads the enum from this file.
 */

// ---- engines ---------------------------------------------------------------

export const GOLPO_ENGINES = ["golpo_canvas", "golpo_sketch"] as const;
export type GolpoEngine = (typeof GOLPO_ENGINES)[number];

// ---- Golpo Canvas style variants (10 base looks; most also have a
// "_compact" density variant — Golpo's "Compact" vs "Expanded" profile) ------

export const GOLPO_CANVAS_STYLE_VARIANTS = [
  "chalkboard_bw",
  "chalkboard_bw_compact",
  "chalkboard_black_on_white",
  "chalkboard_black_on_white_compact",
  "chalkboard_color",
  "chalkboard_color_compact",
  "whiteboard",
  "whiteboard_compact",
  "modern_minimal",
  "modern_minimal_compact",
  "playful",
  "playful_compact",
  "technical",
  "technical_compact",
  "editorial",
  "editorial_compact",
  "sharpie",
  "sharpie_compact",
  "illustrations",
  "illustrations_compact",
  "notebook_infographic",
] as const;
export type GolpoCanvasStyleVariant = (typeof GOLPO_CANVAS_STYLE_VARIANTS)[number];

// ---- Golpo Sketch style variants (9) ---------------------------------------

export const GOLPO_SKETCH_STYLE_VARIANTS = [
  "classic",
  "improved(beta)",
  "formal",
  "crayon",
  "dry_erase",
  "professional_clean",
  "creative",
  "infographics",
  "chalkboard_black_on_white",
] as const;
export type GolpoSketchStyleVariant = (typeof GOLPO_SKETCH_STYLE_VARIANTS)[number];

// ---- Pen-in-Hand — a Canvas-only cursor/drawing-tool modifier, not a third
// engine (Golpo's own guide: "Compatibility: works with all Canvas visual
// styles"). 3 values, matching what the dashboard calls "Pen in Hand". -----

export const GOLPO_PEN_ANIMATION_STYLES = ["pen", "marker", "stylus"] as const;
export type GolpoPenAnimationStyle = (typeof GOLPO_PEN_ANIMATION_STYLES)[number];

// ---- voices, music, pacing --------------------------------------------------

export const GOLPO_VOICES = ["female-1", "female-2", "male-1", "male-2"] as const;
export type GolpoVoice = (typeof GOLPO_VOICES)[number];

export const GOLPO_MUSIC_TRACKS = [
  "jazz",
  "lofi",
  "dramatic",
  "engaging",
  "hyper",
  "inspirational",
  "documentary",
] as const;
export type GolpoMusicTrack = (typeof GOLPO_MUSIC_TRACKS)[number];

export const GOLPO_SCENE_PACINGS = ["normal", "fast"] as const;
export type GolpoScenePacing = (typeof GOLPO_SCENE_PACINGS)[number];

// ---- curated guidance — the actual "what is this style for" knowledge -----

export interface StyleGuidance {
  label: string;
  description: string;
  bestFor: string;
}

export const CANVAS_STYLE_GUIDANCE: Record<GolpoCanvasStyleVariant, StyleGuidance> = {
  chalkboard_bw: {
    label: "Chalkboard (white on black)",
    description: "White chalk lines on a black board, high contrast.",
    bestFor: "Dramatic or high-stakes topics (crisis, conflict, a turning point) where a darker frame fits the mood.",
  },
  chalkboard_bw_compact: {
    label: "Chalkboard (white on black), compact",
    description: "Same as chalkboard_bw with more content packed per scene, fewer scene transitions.",
    bestFor: "The same use as chalkboard_bw, for a topic that's short on `timing` but has several distinct facts to fit.",
  },
  chalkboard_black_on_white: {
    label: "Chalkboard (black on white)",
    description: "Dark chalk-style drawing on a light background — the classic classroom-blackboard feel.",
    bestFor: "Traditional, general-purpose educational explainers with no particular tonal need — the safe default look.",
  },
  chalkboard_black_on_white_compact: {
    label: "Chalkboard (black on white), compact",
    description: "chalkboard_black_on_white with denser scenes.",
    bestFor: "Same as chalkboard_black_on_white when several facts need to land inside a short `timing`.",
  },
  chalkboard_color: {
    label: "Chalkboard, color",
    description: "The chalkboard treatment with full color accents instead of monochrome chalk.",
    bestFor: "Engaging, general-audience educational content that still wants the traditional-classroom credibility but a livelier palette.",
  },
  chalkboard_color_compact: {
    label: "Chalkboard, color, compact",
    description: "chalkboard_color with denser scenes.",
    bestFor: "Same as chalkboard_color when the topic has several distinct facts and a short `timing`.",
  },
  whiteboard: {
    label: "Whiteboard",
    description: "Canvas's plain whiteboard interpretation — clean, neutral, collaborative in tone.",
    bestFor: "General-purpose explainers with no strong stylistic need — a safe, legible fallback.",
  },
  whiteboard_compact: {
    label: "Whiteboard, compact",
    description: "whiteboard with denser scenes.",
    bestFor: "Same as whiteboard for a fact-dense topic on a short `timing`.",
  },
  modern_minimal: {
    label: "Modern minimal",
    description: "Restrained palette, geometric shapes, generous whitespace.",
    bestFor: "Contemporary, process- or system-oriented topics (how something works, a modern institution) — reads as clean and current, not old-fashioned.",
  },
  modern_minimal_compact: {
    label: "Modern minimal, compact",
    description: "modern_minimal with denser scenes.",
    bestFor: "Same as modern_minimal when the topic has several distinct steps to fit in a short `timing`.",
  },
  playful: {
    label: "Playful",
    description: "Brighter palette, more expressive character work.",
    bestFor: "Lighter, approachable topics aimed at a casual or younger-feeling audience — never for a somber or high-stakes subject.",
  },
  playful_compact: {
    label: "Playful, compact",
    description: "playful with denser scenes.",
    bestFor: "Same as playful for a lighter topic with several small facts on a short `timing`.",
  },
  technical: {
    label: "Technical",
    description: "Schematic, blueprint-adjacent feel with clean diagrammatic lines.",
    bestFor: "Process/mechanism topics — how a system, procedure, or piece of machinery actually works, step by step.",
  },
  technical_compact: {
    label: "Technical, compact",
    description: "technical with denser scenes.",
    bestFor: "Same as technical when several process steps need to fit a short `timing`.",
  },
  editorial: {
    label: "Editorial",
    description: "Magazine-style illustration with more designed, composed scenes.",
    bestFor: "Narrative or historical topics that benefit from a designed, story-like visual treatment rather than a plain diagram.",
  },
  editorial_compact: {
    label: "Editorial, compact",
    description: "editorial with denser scenes.",
    bestFor: "Same as editorial for a story-driven topic that still needs to move quickly.",
  },
  sharpie: {
    label: "Sharpie",
    description: "Bold marker-pen strokes, thicker and higher-energy than a pen line.",
    bestFor: "High-energy, presentation-style topics that want punch and confidence over subtlety.",
  },
  sharpie_compact: {
    label: "Sharpie, compact",
    description: "sharpie with denser scenes.",
    bestFor: "Same as sharpie for a fact-dense topic on a short `timing`.",
  },
  illustrations: {
    label: "Illustrations",
    description: "Fuller, scene-led compositions with expressive hand-drawn illustration rather than sparse diagrams.",
    bestFor: "Narrative-driven topics where the story itself is the teaching device (an event, a person, a cause-and-effect chain).",
  },
  illustrations_compact: {
    label: "Illustrations, compact",
    description: "illustrations with denser scenes.",
    bestFor: "Same as illustrations for a longer narrative that needs to fit a shorter `timing`.",
  },
  notebook_infographic: {
    label: "Notebook infographic",
    description: "A structured, notebook-like layout built for organized, step-by-step or data-forward explanations. Compact-only — there is no expanded profile.",
    bestFor: "Data-heavy or highly structured topics (statistics, a numbered list of steps, a labeled comparison) inside the Canvas engine.",
  },
};

export const SKETCH_STYLE_GUIDANCE: Record<GolpoSketchStyleVariant, StyleGuidance> = {
  classic: {
    label: "Classic",
    description: "Golpo Sketch's default hand-drawn whiteboard line art.",
    bestFor: "The safe general-purpose default for a straightforward conceptual explainer with no particular tonal need.",
  },
  "improved(beta)": {
    label: "Improved (beta)",
    description: "A more contemporary iteration of the line-art renderer.",
    bestFor: "Same use as Classic, when a slightly more modern line-art look is preferred and the beta label is acceptable.",
  },
  formal: {
    label: "Formal",
    description: "A more refined line-art treatment with denser composition per scene.",
    bestFor: "Complex or information-dense conceptual topics that need more packed into fewer scenes without switching to Canvas.",
  },
  crayon: {
    label: "Crayon",
    description: "Looser, more illustrative, casual line work.",
    bestFor: "Lighter, friendlier topics aimed at a casual or younger-feeling audience.",
  },
  dry_erase: {
    label: "Dry erase",
    description: "Thicker outlines with an authentic hand-drawn whiteboard-marker feel.",
    bestFor: "Corporate-training-style or traditional-classroom explainers that want the real-whiteboard feeling.",
  },
  professional_clean: {
    label: "Professional clean",
    description: "A pared-back treatment: cleaner lines, more whitespace.",
    bestFor: "Professional or institutional topics (civics, government process, formal procedure) where a minimalist, credible look matters.",
  },
  creative: {
    label: "Creative",
    description: "A newer, more expressive Sketch variant, looser than Classic.",
    bestFor: "Similar to Crayon — approachable, less formal topics that still want a hand-drawn (not Canvas-illustrated) look.",
  },
  infographics: {
    label: "Infographics",
    description: "Data-forward: organizes ideas into labeled diagrams, icons, and callouts instead of a flowing hand-drawn scene.",
    bestFor: "Statistics, numbered comparisons, or any topic whose core content is genuinely numeric or list-shaped.",
  },
  chalkboard_black_on_white: {
    label: "Chalkboard (black on white)",
    description: "Sketch's own chalkboard-styled line art on a light background.",
    bestFor: "Same use as Canvas's chalkboard_black_on_white, when staying on the Sketch engine (e.g. for its faster default pacing) is preferred.",
  },
};

export const PEN_ANIMATION_GUIDANCE: Record<GolpoPenAnimationStyle, StyleGuidance> = {
  pen: {
    label: "Pen in hand",
    description: "A fine-tipped pen draws precise, elegant lines.",
    bestFor: "Clean professional explainers and detailed diagrams — restrained visual styles (modern_minimal, technical, professional_clean-adjacent Canvas looks).",
  },
  marker: {
    label: "Marker in hand",
    description: "A bold marker produces thicker, more confident strokes.",
    bestFor: "The energy of a live whiteboard session — pairs well with sharpie or playful.",
  },
  stylus: {
    label: "Stylus in hand",
    description: "A digital stylus draws on a tablet-like surface — modern, tech-forward.",
    bestFor: "SaaS, product, engineering, and digital-native content — pairs well with modern_minimal or technical.",
  },
};

export const VOICE_GUIDANCE: Record<GolpoVoice, string> = {
  "female-1": "Warm female — the safe general-purpose default for most educational content.",
  "female-2": "Energetic female — lighter, higher-energy topics (pairs with playful/crayon-style visuals).",
  "male-1": "Calm male — measured, formal, or institutional topics.",
  "male-2": "Dramatic male — high-stakes or narrative topics that benefit from gravity.",
};

export const MUSIC_GUIDANCE: Record<GolpoMusicTrack, string> = {
  jazz: "Sophisticated, unobtrusive — professional/institutional topics.",
  lofi: "Calm, background-only — long-form or reflective conceptual topics.",
  dramatic: "High tension — historical turning points, conflict, high-stakes narrative.",
  engaging: "Upbeat, general-purpose — the safe default for most lessons.",
  hyper: "High energy — short, punchy, casual topics.",
  inspirational: "Uplifting — achievement, progress, or civic-participation framing.",
  documentary: "Measured and factual — data-heavy or historical-narrative topics.",
};

// ---- the settings an "AI Art Wisdom" decision actually produces -----------

export interface GolpoSettings {
  engine: GolpoEngine;
  canvasStyleVariant?: GolpoCanvasStyleVariant;
  sketchStyleVariant?: GolpoSketchStyleVariant;
  penAnimationStyle?: GolpoPenAnimationStyle;
  scenePacing: GolpoScenePacing;
  voice: GolpoVoice;
  musicTrack?: GolpoMusicTrack;
  /** Freeform steer for what Golpo actually draws — Golpo's own `visual_instructions` field. */
  visualInstructions?: string;
  /** Freeform steer for narration delivery — Golpo's own `narration_instructions` field. */
  narrationInstructions?: string;
}

const MAX_INSTRUCTION_CHARS = 500;

export const GolpoSettingsSchema = z
  .object({
    engine: z.enum(GOLPO_ENGINES),
    canvasStyleVariant: z.enum(GOLPO_CANVAS_STYLE_VARIANTS).optional(),
    sketchStyleVariant: z.enum(GOLPO_SKETCH_STYLE_VARIANTS).optional(),
    penAnimationStyle: z.enum(GOLPO_PEN_ANIMATION_STYLES).optional(),
    scenePacing: z.enum(GOLPO_SCENE_PACINGS),
    voice: z.enum(GOLPO_VOICES),
    musicTrack: z.enum(GOLPO_MUSIC_TRACKS).optional(),
    visualInstructions: z.string().max(MAX_INSTRUCTION_CHARS).optional(),
    narrationInstructions: z.string().max(MAX_INSTRUCTION_CHARS).optional(),
  })
  .superRefine((value, ctx) => {
    if (value.engine === "golpo_canvas" && !value.canvasStyleVariant) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "canvasStyleVariant is required when engine is golpo_canvas", path: ["canvasStyleVariant"] });
    }
    if (value.engine === "golpo_sketch" && !value.sketchStyleVariant) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "sketchStyleVariant is required when engine is golpo_sketch", path: ["sketchStyleVariant"] });
    }
    if (value.penAnimationStyle && value.engine !== "golpo_canvas") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "penAnimationStyle only applies to golpo_canvas", path: ["penAnimationStyle"] });
    }
  });

/**
 * A safe, reasonable settings object to fall back to if the model's own
 * choice fails validation — never blocks a lesson on a malformed style pick.
 * Deliberately the most generic, broadly-legible combination in the catalog.
 */
export const DEFAULT_GOLPO_SETTINGS: GolpoSettings = {
  engine: "golpo_canvas",
  canvasStyleVariant: "whiteboard",
  scenePacing: "normal",
  voice: "female-1",
  musicTrack: "engaging",
};

/** Renders the whole catalog + guidance as prompt text for the lesson-generation model. */
export function describeGolpoCapabilitiesForPrompt(): string {
  const canvasLines = GOLPO_CANVAS_STYLE_VARIANTS.map((v) => `  - ${v}: ${CANVAS_STYLE_GUIDANCE[v].description} Best for: ${CANVAS_STYLE_GUIDANCE[v].bestFor}`).join("\n");
  const sketchLines = GOLPO_SKETCH_STYLE_VARIANTS.map((v) => `  - ${v}: ${SKETCH_STYLE_GUIDANCE[v].description} Best for: ${SKETCH_STYLE_GUIDANCE[v].bestFor}`).join("\n");
  const penLines = GOLPO_PEN_ANIMATION_STYLES.map((v) => `  - ${v}: ${PEN_ANIMATION_GUIDANCE[v].description} Best for: ${PEN_ANIMATION_GUIDANCE[v].bestFor}`).join("\n");
  const voiceLines = GOLPO_VOICES.map((v) => `  - ${v}: ${VOICE_GUIDANCE[v]}`).join("\n");
  const musicLines = GOLPO_MUSIC_TRACKS.map((v) => `  - ${v}: ${MUSIC_GUIDANCE[v]}`).join("\n");

  return `GolpoAI render engine — pick exactly one engine, one style within it, a voice, and optionally music:

ENGINE "golpo_canvas" (illustrated scenes, 10 base looks, each also available in a denser "_compact" profile):
${canvasLines}
  Canvas only: you may also set penAnimationStyle to change the drawing tool:
${penLines}

ENGINE "golpo_sketch" (hand-drawn whiteboard line art, faster default pacing, 9 styles):
${sketchLines}

VOICES:
${voiceLines}

BACKGROUND MUSIC (optional — omit for narration-only):
${musicLines}

scenePacing: "fast" (tighter, quicker) or "normal" (slower, more deliberate) — Sketch defaults to fast; prefer "normal" for a topic dense enough that a viewer needs a beat to absorb each scene.

You may also set visualInstructions (what Golpo should actually draw/illustrate for this
specific script — concrete, e.g. "show a courtroom with a judge handing down a sentence,
not a generic gavel icon") and narrationInstructions (delivery notes, e.g. "pause slightly
after the key statistic"). Both are optional but are the most direct lever you have over
*which drawing or example* Golpo produces — use them whenever the script's central claim
needs a specific, not generic, illustration (see the dual-coding rule below).`;
}
