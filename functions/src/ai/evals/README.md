# AI tutor evals

Run with:

```
AI_API_KEY=<your key> npm run eval
```

`AI_MODEL` is optional (defaults to the same model the app uses in production, per
`functions/src/ai/modelClient.ts`). Without `AI_API_KEY` set, `npm run eval` still runs —
every case comes back `SKIPPED` rather than faked, which only proves the harness itself
executes end-to-end against the fixtures, not that the prompts are any good.

Nothing in this sandbox has model API credentials, so every run here has been done by the
user, on their machine. Paste the printed table over the one below after any prompt or
model change — that's the whole point of keeping this file current rather than a one-time
check.

## What's covered

- `fixtures.ts`: 5 hand-written `GroundingContext`s — two mirror the real seeded civics
  topic (one passed cleanly, one failed a specific question), plus a no-transcript video
  (the honest-degradation path), a no-quiz video with existing thread history (continuity
  without a quiz to fall back to), and a transcript well over the truncation budget.
- `cases.ts`: 21 cases across those fixtures — full six-category coverage (in-scope,
  out-of-scope, partially-correct, confidently-wrong, "I don't know", hostile/off-topic)
  on the two civics fixtures and the no-transcript one; a smaller, scenario-focused subset
  on the other two rather than mechanically repeating all six where they'd just re-test
  the same prompt-assembly logic already covered.
- `run.ts` checks, deterministically, per case:
  - response length under the mode's word limit (80 discuss / 60 quizMe)
  - the `<<<META>>>` structured-output block parses successfully
  - exactly one `?` in a `quizMe` response (a proxy for "exactly one question per turn" —
    imperfect, since a question can legitimately contain a clause with its own `?`-free
    aside, but a fast, real, zero-cost check worth having)
  - `retentionAssessment` is set (non-null) whenever a `quizMe` turn should have evaluated
    an answer

## What's *not* covered yet

The spec also asks for a model-graded rubric — "stays within the lesson's content", "never
states a fact that contradicts the transcript", "partially correct answers get the correct
part acknowledged first". Those need actual judgment, not a regex, which means either a
second model call per case (a real cost, and its own prompt to get right) or human review
of the transcript this script prints. Building that grading pass is real, scoped-out work,
not an oversight — flagging it here rather than a rubric that quietly never ran.

## Known limitation: the metadata block isn't always emitted

Two real runs (below) show the model doesn't reliably attach the `<<<META>>>` block (or
sets `retentionAssessment` to `null` when it shouldn't) on every turn that needs it —
strengthening the wording in `prompts.ts` (`v1` → `v2`) narrowed but did not close this.
This is a known limit of asking a model to append a free-text-delimited block via prose
instructions alone; the actual fix is structural — forcing the metadata through Anthropic's
tool-use mechanism (a schema-constrained tool call) instead of hoping the model remembers —
which is real work across the streaming path (`modelClient.ts`, `aiTutorMessage.ts`,
`prompts.ts`), not a wording tweak. Deliberately not built yet: `parseModelOutput` already
degrades gracefully when this happens (no crash — just no suggested-reply chips and no SM-2
due-date pull-forward for that turn), the same "degrade honestly" pattern used elsewhere in
this phase, so accepted as a known, non-blocking gap rather than a phase blocker. Revisit
if it turns out to happen often enough in real use to matter.

## Scores

**2026-08-05, `AI_MODEL=claude-sonnet-5`, prompts `v1`.** All 21 cases ran (no `SKIPPED`,
no `ERROR`) and every word-limit/format/one-question-mark check passed. 3 cases failed the
retention-set check: `cbg-partial`, `cbg-dontknow`, `cbr-dontknow` — the model sometimes
left `retentionAssessment` null on a "partial answer" or "I don't know" turn instead of
tagging it `shaky`/`missed`. This run predates two fixes made in response to it, so its
raw exit code doesn't reflect them:

1. `run.ts`'s pass/fail gate never actually checked the retention-set column — it would
   have reported "0 failed" and exit 0 despite the 3 failures visible in its own table.
   Fixed to include `retentionSetWhenExpected` in the failure filter.
2. `OUTPUT_FORMAT_INSTRUCTION` in `prompts.ts` didn't explicitly say that "I don't know"
   or a partial/hedging answer still counts as an evaluated turn — strengthened to say so
   directly (bumped to prompts `v2`).

Re-run needed against `v2` to confirm the fix actually closes the gap before this is
considered a clean pass.

| case | category | words | ≤limit | format ok | 1 question | retention set |
|---|---|---|---|---|---|---|
| cbg-in-scope | in-scope | 28 | ✅ | ✅ | n/a | n/a |
| cbg-out-of-scope | out-of-scope | 52 | ✅ | ✅ | n/a | n/a |
| cbg-partial | partial-credit | 52 | ✅ | ✅ | ✅ | ❌ |
| cbg-wrong | confidently-wrong | 29 | ✅ | ✅ | ✅ | ✅ |
| cbg-dontknow | dont-know | 40 | ✅ | ✅ | ✅ | ❌ |
| cbg-hostile | hostile | 31 | ✅ | ✅ | n/a | n/a |
| cbr-session-start | session-start | 15 | ✅ | ✅ | ✅ | n/a |
| cbr-in-scope | in-scope | 45 | ✅ | ✅ | n/a | n/a |
| cbr-out-of-scope | out-of-scope | 50 | ✅ | ✅ | n/a | n/a |
| cbr-partial | partial-credit | 36 | ✅ | ✅ | ✅ | ✅ |
| cbr-wrong | confidently-wrong | 37 | ✅ | ✅ | ✅ | ✅ |
| cbr-dontknow | dont-know | 26 | ✅ | ✅ | ✅ | ❌ |
| nt-session-start | session-start | 26 | ✅ | ✅ | n/a | n/a |
| nt-in-scope | in-scope | 43 | ✅ | ✅ | n/a | n/a |
| nt-out-of-scope | out-of-scope | 73 | ✅ | ✅ | n/a | n/a |
| nt-partial | partial-credit | 48 | ✅ | ✅ | ✅ | ✅ |
| nt-hostile | hostile | 55 | ✅ | ✅ | n/a | n/a |
| nq-in-scope | in-scope | 27 | ✅ | ✅ | n/a | n/a |
| nq-out-of-scope | out-of-scope | 60 | ✅ | ✅ | n/a | n/a |
| lt-in-scope | in-scope | 57 | ✅ | ✅ | n/a | n/a |
| lt-session-start | session-start | 24 | ✅ | ✅ | n/a | n/a |

---

**2026-08-05 (same day, second run), `AI_MODEL=claude-sonnet-5`, prompts `v2`.** Run
against the `v2` prompt strengthening above and the fixed pass/fail gate — which is why
this run correctly reports "5 case(s) failed a deterministic assertion" instead of a false
"0 failed" the way the pre-fix harness would have. Two distinct failure patterns:

- **2 word-limit overruns** (`nt-out-of-scope` 91w, `nt-partial` 72w) — both passed
  comfortably in run 1 (73w, 48w) on the same fixture/case. Most likely ordinary sampling
  variance (no fixed temperature/seed), not a regression — worth another run or two to see
  if it's consistently borderline for the no-transcript fixture specifically.
- **3 metadata-compliance failures** (`cbg-partial`, `cbg-dontknow`, `cbr-dontknow`) — the
  `v2` wording change narrowed but did not close the gap run 1 found: `cbg-dontknow` still
  left `retentionAssessment` null with the meta block otherwise present, and two cases
  (`cbg-partial`, `cbr-dontknow`) omitted the meta block entirely, a failure mode not seen
  in run 1. Confirmed not a token-budget truncation artifact — `maxTokens: 500` (same value
  the real callable uses) is far more than these 20-90 word responses need. **Decision:**
  accepted as a known, non-blocking model-reliability limitation rather than pursued
  further right now — see the section above. Revisit with the tool-use structural fix if
  this proves common enough in real usage to matter.

| case | category | words | ≤limit | format ok | 1 question | retention set |
|---|---|---|---|---|---|---|
| cbg-in-scope | in-scope | 30 | ✅ | ✅ | n/a | n/a |
| cbg-out-of-scope | out-of-scope | 40 | ✅ | ✅ | n/a | n/a |
| cbg-partial | partial-credit | 20 | ✅ | ❌ | ❌ | ❌ |
| cbg-wrong | confidently-wrong | 29 | ✅ | ✅ | ✅ | ✅ |
| cbg-dontknow | dont-know | 20 | ✅ | ✅ | ✅ | ❌ |
| cbg-hostile | hostile | 42 | ✅ | ✅ | n/a | n/a |
| cbr-session-start | session-start | 15 | ✅ | ✅ | ✅ | n/a |
| cbr-in-scope | in-scope | 26 | ✅ | ✅ | n/a | n/a |
| cbr-out-of-scope | out-of-scope | 46 | ✅ | ✅ | n/a | n/a |
| cbr-partial | partial-credit | 49 | ✅ | ✅ | ✅ | ✅ |
| cbr-wrong | confidently-wrong | 40 | ✅ | ✅ | ✅ | ✅ |
| cbr-dontknow | dont-know | 26 | ✅ | ❌ | ❌ | ❌ |
| nt-session-start | session-start | 20 | ✅ | ✅ | n/a | n/a |
| nt-in-scope | in-scope | 41 | ✅ | ✅ | n/a | n/a |
| nt-out-of-scope | out-of-scope | 91 | ❌ | ✅ | n/a | n/a |
| nt-partial | partial-credit | 72 | ❌ | ✅ | ✅ | ✅ |
| nt-hostile | hostile | 40 | ✅ | ✅ | n/a | n/a |
| nq-in-scope | in-scope | 23 | ✅ | ✅ | n/a | n/a |
| nq-out-of-scope | out-of-scope | 64 | ✅ | ✅ | n/a | n/a |
| lt-in-scope | in-scope | 63 | ✅ | ✅ | n/a | n/a |
| lt-session-start | session-start | 21 | ✅ | ✅ | n/a | n/a |
