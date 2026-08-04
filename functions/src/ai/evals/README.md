# AI tutor evals

Run with:

```
AI_API_KEY=<your key> npm run eval
```

`AI_MODEL` is optional (defaults to the same model the app uses in production, per
`functions/src/ai/modelClient.ts`). Without `AI_API_KEY` set, `npm run eval` still runs —
every case comes back `SKIPPED` rather than faked, which only proves the harness itself
executes end-to-end against the fixtures, not that the prompts are any good.

**This has not been run against a real model yet.** Nothing in this sandbox has model API
credentials, so the table below is the harness's shape, not real scores. Run it for real
once `AI_API_KEY` is available, paste the printed table over the one below, and re-run
after any prompt or model change — that's the whole point of keeping this file current
rather than a one-time check.

## What's covered

- `fixtures.ts`: 5 hand-written `GroundingContext`s — two mirror the real seeded civics
  topic (one passed cleanly, one failed a specific question), plus a no-transcript video
  (the honest-degradation path), a no-quiz video with existing thread history (continuity
  without a quiz to fall back to), and a transcript well over the truncation budget.
- `cases.ts`: 22 cases across those fixtures — full six-category coverage (in-scope,
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

## Scores

_Not yet run. Paste `npm run eval`'s table output here after a real run, and note the date
and `AI_MODEL` value alongside it._
