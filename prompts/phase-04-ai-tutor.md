# Phase 4 — The AI tutor

Read `prompts/README.md` first. Phases 0–3 must be merged and building.

## Goal

Build the feature behind the `sparkles` button in the feed's right rail: a tutor that
discusses the lesson the learner just watched, and — more importantly — *quizzes them
conversationally* to check retention. The multiple-choice quiz from Phase 2 verifies
recognition. This verifies understanding.

This is the app's actual differentiator. A generic chatbot bolted onto a video is worth
nothing; a tutor that knows exactly what this video taught, what this learner got wrong,
and asks the follow-up question a good teacher would ask is worth the whole build.

## 1. Two modes, one thread

The AI sheet opens on the current video with a mode toggle at the top:

**Discuss** (default) — the learner asks; the tutor answers, grounded in this video and
topic. Opens with a suggestion row of three generated starter questions specific to the
video, so the learner isn't staring at an empty box.

**Quiz me** — the tutor asks; the learner answers in free text; the tutor evaluates,
explains, and follows up. This is a spoken-style oral check, not multiple choice. Three
to five exchanges, then a short summary of what looked solid and what to review.

Both modes write into the same `videos/{videoId}/aiThreads/{uid}/messages` thread from
Phase 1, so context carries across mode switches and across sessions on the same video.
Store `mode` on each message so the transcript reads correctly later.

## 2. Grounding — the part that determines whether this is any good

The tutor must only teach from what the video actually taught. Assemble context
server-side, never client-side:

1. **Video**: title, description, and `transcript`.
2. **Topic**: title, description, and the titles of the videos before and after this one
   (so "we covered that in the next lesson" is possible).
3. **Quiz**: the questions, correct answers, and explanations for this video.
4. **This learner's record on this video**: quiz attempts, best score, which specific
   questions they got wrong, and `masteryPercent` for the topic. This is what makes the
   tutor feel like it's paying attention — it should open a "Quiz me" session by probing
   exactly what they missed.
5. **Recent thread history**: last 10 messages.

**Transcript is the load-bearing input.** Without it the tutor is guessing from a title.
Handle it in this order:
- If the creator supplied a transcript in Phase 5, use it.
- Otherwise, generate one: a Cloud Function triggered on `status: "ready"` submits the
  R2 object to a speech-to-text API and writes `transcript` plus
  `transcriptSource: "auto"`. Store word-level timings if the API returns them —
  Phase 6 can use them for captions.
- If neither exists, the AI button is still enabled but the tutor opens by saying it
  only has the lesson summary to work from, and "Quiz me" falls back to quizzing from
  the multiple-choice questions. Degrade honestly; never pretend.

## 3. Server architecture

All model calls go through a Cloud Function. **No model API key may ever exist in the
iOS app** — a key in a shipped binary can be extracted from the IPA.

### Callable / streaming endpoint: `aiTutorMessage`

Auth: signed-in, non-guest. Guests get the sign-in sheet before the tutor opens.

Input: `{ videoId, mode: "discuss" | "quizMe", text?, isSessionStart: boolean }`.

Flow:
1. Verify the learner may read this video.
2. Look up the caller's tier (`users/{uid}.tier`, defined in
   `prompts/phase-07-lessons-on-demand.md` §4) and resolve it to a model and a pair of
   caps via the shared `TIERS` constant — see Guardrails below. This replaces a single
   Function-config model choice with a per-tier one.
3. Assemble the context above from Firestore.
4. Build the prompt (see §4) and call the model.
5. **Stream the response.** Use an HTTPS Function with SSE (or Firestore-document
   streaming if that proves simpler on iOS) so text appears token by token. A tutor that
   pauses for six seconds then dumps a paragraph feels broken.
6. Persist both the user message and the assistant message; update thread metadata.
7. Return, alongside the text, structured hints the UI can act on:
   `{ suggestedReplies: string[], retentionAssessment?: { questionIds: string[], verdict: "solid" | "shaky" | "missed" } }`.

When `retentionAssessment` reports `missed` or `shaky` for a question, update that
video's `videoProgress` review state — a conversational miss should pull the video
forward in the review queue exactly as a failed multiple-choice question does. Reuse the
Phase 1 SM-2 code path; do not invent a second scheduler.

### Guardrails

**Superseded by the tier pivot** — this used to be one flat rate limit and one
Function-config model for every user. It's now per-tier on both axes, sourced from the
same `TIERS` constant Phase 7 defines (`functions/src/lib/tiers.ts`), so there is one
place these numbers live, not a copy in each phase:

| Tier | Model | Daily message cap | Monthly cost cap |
|---|---|---|---|
| Free | Haiku 4.5 | 20/day | — |
| Siltstone | Haiku 4.5 | 20/day | — |
| Obsidian | Sonnet 5 | 20/day | $3.00/cycle |
| Alabaster | Sonnet 5 | 40/day | $7.00/cycle |
| Pyramidion | Sonnet 5 | 100/day | $20.00/cycle |

- **Model selection is tier-driven, not a single `AI_MODEL` config value.**
  `AnthropicModelClient` now takes the model explicitly per call
  (`new AnthropicModelClient(TIERS[tier].aiModel)`) instead of defaulting to
  `aiModel.value()`. `AI_MODEL` Function config stays only as the eval harness's
  override (`functions/src/ai/evals/run.ts` already reads `process.env.AI_MODEL`) —
  the production path no longer has one global model.
- **Daily message cap replaces the old flat 30/hour, 300/day pair with one per-tier
  daily number** — the hourly sub-limit is dropped; each tier now specifies only a
  daily cap, and the new monthly cost cap (below) is the second layer of protection the
  old design didn't have. Still tracked in `users/{uid}/aiUsage/{yyyy-mm-dd}`, same
  transactional check-and-increment `rateLimit.ts` already does — just read the cap
  from `TIERS[tier].aiDailyMessageCap` instead of a hardcoded constant.
- **Monthly cost cap (Obsidian and above) is a real dollar ceiling, not another message
  count — "unlimited chat, but stop at $X" is the actual product promise, so it has to
  be enforced against real spend.** This requires a genuine capability the code doesn't
  have yet: `ModelClient.stream()` currently returns only the accumulated text and
  silently discards the Anthropic response's `usage` (confirmed by direct
  measurement — real per-message cost ranges from under a cent on Haiku to several
  cents on Sonnet for a long-transcript context, so message count alone is a poor proxy
  for real cost). Extend `StreamParams`/`ModelClient.stream()` to also return
  `{ inputTokens, outputTokens }` from the API response, and give `FakeModelClient` a
  deterministic stand-in (e.g. token count from `scriptedResponse.length / 4`) so evals
  and unit tests keep working without a real key. Accumulate **exact integer token
  totals** — not a pre-computed, repeatedly-rounded cents figure — in a new
  `users/{uid}/aiUsage/{yyyy-mm}` doc (`inputTokensThisCycle`, `outputTokensThisCycle`),
  and compute the real cost in cents from a small versioned pricing table
  (`functions/src/ai/pricing.ts`, one row per model, updated when list prices change)
  only at check time. This avoids compounding rounding error across hundreds of
  sub-cent additions, the same reason Phase 7's credit ledger is cents-integer rather
  than float dollars.
- **Both caps are checked together, before the model call, in the same transaction as
  the daily counter increment.** Whichever binds first refuses the message with a typed
  error naming which cap and when it resets: the daily cap resets at the next UTC day
  boundary; the monthly cost cap resets on that tier's billing-cycle boundary (Stripe's
  `invoice.paid` for Obsidian/Alabaster; the balance-triggered-or-30-day recharge event
  for Pyramidion, per `phase-07-lessons-on-demand.md`'s billing mechanics — one
  cycle-reset event zeroes both the like-refund counter and this cost counter for
  Pyramidion).
- **Free and Siltstone get no cost cap** — Haiku's per-message cost is small enough
  that the daily count alone is a sufficient guardrail; adding a dollar cap there would
  be complexity with no real protection behind it.
- **Cost ceiling on any single call**: cap context and output tokens; truncate
  transcripts to a token budget by keeping the segments most relevant to the learner's
  question.
- **Abuse**: reject inputs over 2000 characters. If a learner steers the conversation
  far off the lesson, the tutor redirects once, then declines and offers to answer
  something about the lesson instead.
- **Secrets**: model API key in Function secrets (`AI_API_KEY`). Log token counts, never
  message contents, to your metrics.

## 4. Prompting

Put the system prompt in `functions/src/ai/prompts.ts` as a versioned template, not
inline in the handler. Log the `promptVersion` on each message so regressions are
traceable.

The tutor's character:
- A patient, specific teacher. Warm without being saccharine. No emoji unless the
  learner uses them.
- **Short turns.** Two to four sentences by default. This is a phone sheet over a video,
  not an essay. Length is the single most common failure mode here — constrain it
  explicitly and check it in evals.
- **Never fabricate.** If the lesson doesn't cover something, say so plainly, then offer
  what the lesson *does* say. For factual questions beyond the transcript, it may give
  general knowledge but must mark it as outside this lesson.
- **Socratic in "Quiz me".** Ask one question at a time. Never ask a question and answer
  it in the same turn. When an answer is partly right, name the correct part before the
  gap — and never simply say "wrong."
- **Evaluate meaning, not wording.** A learner who gets the concept with different words
  is correct. This is the whole reason for free-text over multiple choice.
- If a learner seems discouraged, respond to that before continuing to drill.

Write separate templates for `discuss` and `quizMe`, sharing a common preamble that
carries the grounding context.

## 5. iOS implementation

`AITutorSheet` presented from the feed rail:

- Chat transcript with the tutor's messages left, the learner's right, matching the
  Phase 3 comment styling so the app feels of one piece.
- Streaming text renders progressively with a cursor; a three-dot indicator shows before
  the first token.
- Mode toggle as a segmented control at the top. Switching mid-thread inserts a divider
  ("Quiz me") rather than clearing history.
- Suggested-reply chips above the composer, tappable to send, refreshed from each
  response.
- The video stays paused behind the sheet. Dismissing resumes it where it was.
- Thread history loads from Firestore on open, so reopening a video resumes the
  conversation.
- Guest → sign-in sheet before the tutor opens.
- Rate-limit, network-failure, and empty-transcript states each get a specific inline
  message, never a generic "Something went wrong."
- `AITutorRepository` (the protocol stubbed in Phase 1) gets its live implementation
  here plus a scripted fake for previews and tests.

## 6. Evaluation — do not skip this

An untested prompt is a guess. Build `functions/src/ai/evals/`:

- **Fixtures**: 8–10 real video contexts (use the seeded civics topic plus a couple of
  hand-written ones) with transcripts, quizzes, and synthetic learner records.
- **Cases per fixture**: an in-scope question, an out-of-scope question, a partially
  correct free-text answer, a confidently wrong answer, a "I don't know", and a
  hostile/off-topic prompt.
- **Assertions**, scored by a model-graded rubric plus deterministic checks:
  - stays within the lesson's content, or explicitly flags when it doesn't
  - response under 80 words in `discuss`, under 60 in `quizMe`
  - exactly one question per `quizMe` turn
  - partially correct answers get the correct part acknowledged first
  - never states a fact that contradicts the transcript
  - `retentionAssessment` matches the obviously-correct verdict on the scripted cases
- Run as `npm run eval` and record a scores table in `functions/src/ai/evals/README.md`.
  Re-run and update it whenever the prompt or model changes.

## 7. Verify

1. Open AI on a video with a transcript: three relevant starter questions appear, and an
   in-scope question gets a grounded, short answer.
2. Ask something the video never covers: the tutor says so instead of inventing an
   answer.
3. "Quiz me" asks one question at a time and evaluates a correctly-worded-differently
   answer as correct.
4. A conversationally missed concept moves that video's `dueDate` earlier in Firestore.
5. Reopening the same video restores the thread.
6. Exceeding the daily message cap shows the cap message with a reset time, using each
   tier's own number (Free/Siltstone 20, Obsidian 20, Alabaster 40, Pyramidion 100).
   A Free-tier account is served Haiku for every message; an Obsidian-and-above
   account is served Sonnet. Simulating enough Sonnet usage in the emulator to cross
   an Obsidian test account's $3.00 monthly cost cap (using `FakeModelClient`'s
   deterministic token stand-in, not a real spend) refuses further messages with a
   cap message naming the dollar cap and its cycle-end reset — verify this fires from
   accumulated real token counts, not from a hardcoded message count standing in for
   cost.
7. A video with no transcript still opens the tutor, with the honest degraded opener.
8. Guest tapping AI gets the sign-in sheet.
9. `git grep` finds no model API key anywhere in the iOS target.
10. `npm run eval` passes the assertion thresholds; the scores table is committed.

## Out of scope

Voice input/output (a strong later addition — spec it separately), tutor personas,
cross-video or cross-topic tutoring, tutor-generated new quiz questions written back to
the video's quiz.
