# Shui branding — the mark

**Status: selected direction, PNG exports only. No production vector files yet.**

## The mark

"The Threaded Current" — the water-current stroke runs *behind* "Shui," showing
through the letters' counters and disappearing behind their strokes, so the word
and the water idea read as one drawing rather than an icon next to a name. Full
design rationale and every direction considered: `round1-mark-concepts.html`
through `round4-threaded-current-final.html` below, in order.

## Files

| File | What it is |
|---|---|
| `shui-logo-primary.png` | Primary lockup — foam word, current-bright thread, on ink. App icon, splash, marketing, social. Rendered at 3x from a real browser (Fraunces italic, exact production CSS), opaque background. |
| `shui-watermark.png` | Ink word, current thread, transparent background. For the small corner watermark burned into every generated lesson (`prompts/phase-07-lessons-on-demand.md` §4) — this pairing exists because the primary pairing is unreadable on GolpoAI's light whiteboard-style video background; see round 4's "Applied" section for the side-by-side proof. |
| `round1-mark-concepts.html` | Six abstract mark directions before the wordmark was added. |
| `round2-wordmark-lockups.html` | Same six, each paired with "Shui" as an icon+wordmark lockup. |
| `round3-unified-logotypes.html` | Five directions where the water idea lives inside the lettering itself, no separate icon. The Threaded Current is #1 here. |
| `round4-threaded-current-final.html` | The Threaded Current selected and built out: four color pairings, a legibility check on light/dark/brand grounds, and the app-icon vs. watermark distinction. This is the source of truth for the current design. |

Open any `.html` file directly in a browser — they're self-contained, no build step.

## Palette

| Name | Hex | Use |
|---|---|---|
| Ink | `#0F2830` | Primary dark ground; watermark word color |
| Current | `#2E7A88` | Watermark thread color (readable on light video backgrounds) |
| Current Bright | `#6FC2CD` | Primary lockup thread color (on ink) |
| Foam | `#EEF4F1` | Primary lockup word color; light ground |
| Stone | `#8B9089` | Secondary text |
| Brass | `#C79A5C` | Sparing accent only |

## Type

Fraunces (Google Fonts), italic, weight ~460, `font-variation-settings: "SOFT" 75`.

## Not done yet

- **No real vector (SVG/AI) file for the wordmark.** The word is live Fraunces
  text in every file here, not outlined paths — nothing in this session's
  environment can outline a webfont into production vector paths. The PNGs
  above are accurate renders (real browser, real font) but are raster, not
  vector.
- **The current-stroke geometry is an approximation**, not yet cleaned up to
  thread through the *actual* letter counters precisely (round 4's own closing
  note flags this).
- Stroke widths aren't yet locked at reference sizes (icon / watermark / full
  lockup) — the PNGs above are single fixed-size exports, not a scalable system.

Next real step: take this into a vector tool (Figma/Illustrator) to outline the
type and hand-tune the stroke path, then re-export a true SVG/PDF set.
