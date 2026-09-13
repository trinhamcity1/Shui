import { describeGolpoCapabilitiesForPrompt } from "./golpoCapabilities";

/**
 * "AI Art Wisdom" — the one place that connects three things for every
 * on-demand lesson: the topic/idea the learner asked for, what GolpoAI is
 * actually capable of drawing (golpoCapabilities.ts), and the teaching
 * methodology Shui has already validated in a sibling project. This module
 * produces the prompt text `generateLesson.ts` splices into its system
 * prompt — it doesn't call the model itself, so it stays a pure, unit-
 * testable string builder (see `describeGolpoCapabilitiesForPrompt`'s own
 * doc comment for the "reasoned opinion, not proven research" caveat, which
 * applies here too).
 *
 * The methodology rules below are adapted from
 * github.com/trinhamcity1/Shui-Whiteboard-Generator's
 * `src/schema/methodology.ts` (shui-wg-phase-06-teaching-methodology.md) —
 * that project's own system prompt for a *scene-graph* planner (it builds
 * an explicit JSON scene tree: titleCard, sketchDiagram nodes, bulletList,
 * etc., each with its own emphasis/decoration fields). Shui's on-demand
 * pipeline hands GolpoAI a plain narration script and a small set of
 * top-level settings instead — GolpoAI does its own scene-splitting
 * internally, so Shui has no scene-graph to apply "emphasis" or "decoration"
 * fields to directly. The nine techniques are engine-agnostic (they're
 * about how people learn, not about a particular renderer's JSON shape), so
 * they're reframed below as rules for the SCRIPT'S WORDING and for the
 * choice of `visualInstructions`/`golpoSettings` — the two levers Shui
 * actually has. When Shui WG (the self-hosted, per-scene renderer described
 * in that same repo's README) eventually comes online as a second engine,
 * the original scene-graph phrasing becomes relevant again; until then this
 * is the honest translation of the same wisdom onto what Golpo accepts.
 */
export const METHODOLOGY_RULES = `Teaching & retention rules (adapted from Shui's own validated teaching-methodology
research — apply these to the SCRIPT'S WORDING and to your visualInstructions choice,
since GolpoAI does its own scene-splitting and there is no scene graph to hand it):
- RETRIEVAL PRACTICE: identify the single most important, most quiz-able fact in the
  topic before writing. State it plainly, in one self-contained sentence somewhere in
  the script, worded so a listener who heard only that sentence could answer a direct
  question about it. This is also exactly what the quiz's first question should test.
- DUAL CODING, TIGHTENED: your visualInstructions must depict the EXACT claim the
  script is making at that moment, never a generic mood-setting image for the general
  topic. Test: if a viewer saw only what visualInstructions describes, muted, could
  they guess the specific claim? ("a courtroom" fails if the actual claim is about a
  judge's sentencing power specifically — "a judge handing down a sentence" passes.)
- CHUNKING: one idea per sentence/beat. Never join two distinct claims with "and" in a
  single sentence ("Congress writes the law and the President enforces it") — give
  each claim its own sentence so GolpoAI's own scene-splitting naturally gives each
  its own scene, rather than compressing two facts into one that a viewer only half-
  absorbs.
- CONTRAST: when the topic has a natural, well-known misconception ("people think X,
  but actually Y"), reach for it proactively in the script — a misconception ->
  correction beat is one of the strongest retention devices available. Don't wait to
  be asked; if a real misconception exists for this topic, use it.
- THE NARRATIVE HOOK: open on a stake, a scenario, or a "why does this matter"
  framing — never a dictionary-style definition of the topic as the first sentence. A
  script that opens "Federalism is a system of government that..." is weaker than one
  that opens on the tension or consequence the rest of the script resolves.
- CONCRETE, SPECIFIC FRAMING: prefer concrete, imageable phrasing over abstraction.
  "The government has three branches" is abstract; "Congress writes the law, the
  President enforces it, the Courts decide if it's fair" is concrete — same fact, more
  memorable. If a sentence could describe five different topics unchanged, name the
  actual people, actions, or objects instead.`;

export type ContentArchetype = "conceptual" | "process" | "comparison_or_myth_busting" | "data_or_statistics" | "narrative_or_historical" | "casual_or_engaging";

export const CONTENT_ARCHETYPE_GUIDANCE = `Before picking Golpo settings, classify the topic into the ONE content archetype it
fits best — this is what should actually drive your engine/style choice, not a random
pick:
- "conceptual" — defining or explaining an abstract idea (what is X, why does X exist).
  Favor a chalkboard/whiteboard Canvas look or Sketch Classic/Professional Clean —
  traditional, credible, no strong stylistic need.
- "process" — a sequence of steps or how a mechanism/system works. Favor Canvas
  "technical" or "notebook_infographic", or Sketch "formal" — diagrammatic, sequential.
- "comparison_or_myth_busting" — the script's core move is a contrast (a common
  misconception corrected, or two things compared). Favor Canvas "modern_minimal" or
  "editorial" — clean enough that a two-sided comparison reads clearly.
- "data_or_statistics" — the topic is genuinely numeric or list-shaped (a statistic, a
  ranked list, a labeled breakdown). Favor Canvas "notebook_infographic" or Sketch
  "infographics" — Golpo's only two styles actually built for data density.
- "narrative_or_historical" — a story, an event, a person, a cause-and-effect chain
  through time. Favor Canvas "editorial" or "illustrations", or Sketch "creative" —
  scene-led, not diagram-led.
- "casual_or_engaging" — a light, fun framing for a broad or younger-feeling audience.
  Favor Canvas "playful" or Sketch "crayon"/"creative".`;

/**
 * The full prompt section `generateLesson.ts` splices in — methodology,
 * archetype classification, and the complete Golpo capability catalog,
 * combined. Kept as one function so there is exactly one place that decides
 * what "AI Art Wisdom" actually tells the model, in one read order: how to
 * write it, what kind of content it is, then what Golpo can draw for it.
 */
export function buildArtWisdomPromptSection(): string {
  return `${METHODOLOGY_RULES}

${CONTENT_ARCHETYPE_GUIDANCE}

${describeGolpoCapabilitiesForPrompt()}`;
}
