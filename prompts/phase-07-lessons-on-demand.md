# Phase 7 — Lessons on demand

Read `prompts/README.md` first. Phases 0–5 must be merged (Phase 6 is independent —
this phase does not touch the web dashboard). Also depends on the Shui-WG repo
(`shui-whiteboard-generator`) having its quiz-generation feature merged — the
`generateQuiz`/`quizMaxQuestions` request fields and the `quiz` field on
`GET /v1/videos/:id`, both live as of that repo's `quizGeneration.ts` addition.

## Goal

The shareholder direction: Shui is not just a curated-content feed anymore. A learner
should be able to type *any* topic — "explain database normalization," "how boutique
culinary practice affects data modeling," a term from their biology class — and get a
real lesson generated for them personally, landing in their own library, still ending
in a quiz like every other lesson in this app.

**This is a generation client feature, not a new content system.** Shui-WG (a separate
product, with its own web app for people generating videos directly) does the actual
video + quiz generation. Shui's job is: take a topic from a learner, call Shui-WG,
and slot the result into the exact same feed/quiz/progress machinery every other video
already uses.

## 1. Non-negotiable constraint

**No new collection, no new grading path, no new security rule.** An on-demand lesson
is a normal `videos` document with a normal `quiz/current` + `quiz/answers` pair,
belonging to a synthetic **personal topic** owned by the learner
(`topics/personal-{uid}`). This means, unchanged:

- `submitQuizAttempt` grades it, updates `videoProgress`/`topicProgress`, runs SM-2,
  updates streaks — exactly as it does for a curated video. Do not fork this function.
- `firestore.rules`'s existing `isVideoOwnerOrAdmin` / `isTopicOwnerOrAdmin` already
  grant the learner read access to their own private topic and its videos. **No rules
  change is needed for reads.** The personal topic and its videos are written by a
  Cloud Function via the Admin SDK (same pattern `createVideoUpload`/
  `finalizeVideoUpload` already use to bypass the client-write-denied rule on
  `videos`), which is also how this sidesteps `topics`' `allow create: if isCreator()`
  restriction — an on-demand lesson must be available to any signed-in learner, not
  only creators, and a privileged Function write is exactly the existing precedent for
  that.
- `videoIsPublic`/`topicIsPublic` require `visibility == 'public'`. The personal topic
  and every video under it are created with `visibility: "private"` and
  `topicVisibility: "private"` — invisible in Explore, invisible to anyone but the
  owner and admins, with zero new filtering logic needed anywhere a public feed is
  already queried.
- **Reuse `QuizInputSchema` and `splitQuizForStorage`** (`functions/src/schemas/quiz.ts`)
  to validate and write the quiz Shui-WG returns — do not write a second quiz-storage
  path. Shui-WG's response needs one small adapter (below), not a parallel writer.

This is a different feature from the existing `suggestQuizQuestions` (Phase 5's
AI-drafted-questions button in the creator quiz builder) — that one drafts *editable
suggestions* a human reviews and saves via `saveQuiz`; this one is a fully automated
pipeline with no review step, because a personal on-demand lesson has no creator in the
loop. Leave `suggestQuizQuestions` untouched.

## 2. The Shui-WG contract

Shui-WG's API is `POST /v1/videos/generate` (`x-api-key` header) → `202` with
`{job_id}` → poll `GET /v1/videos/:id` until `status` is `ready` or `failed`. Request:

```json
{
  "topic": "how boutique culinary practice affects data modeling",
  "targetDurationSeconds": 90,
  "voice": "<a fixed voice id Shui picks — not user-selectable in this phase>",
  "styleVariant": "classic-whiteboard",
  "orientation": "vertical",
  "generateQuiz": true,
  "quizMaxQuestions": 3
}
```

On `ready`, the job response includes `result_url` (the finished mp4) and `quiz`:

```json
{
  "quiz": {
    "quizCurrent": { "version": 1, "questions": [{ "id": "q1", "prompt": "...", "options": [{"id":"correct","text":"..."}, ...], "requiredCorrectCount": 1, "orderIndex": 0 }], "passThreshold": 0.6 },
    "quizAnswers": { "version": 1, "answers": [{ "id": "q1", "correctOptionIds": ["correct"], "explanation": "..." }] }
  }
}
```

**Adapter, not a new writer:** join `quizCurrent.questions` and `quizAnswers.answers`
by `id` into `QuizInputSchema`'s per-question shape
(`{id, prompt, options, correctOptionIds, requiredCorrectCount, explanation, orderIndex}`),
wrap with the new `videoId`, `QuizInputSchema.parse(...)` it (this validates it exactly
as strictly as a human-authored quiz would be), then call `splitQuizForStorage` and
write both docs — same three calls `saveQuiz` already makes, just invoked from a
different callable instead of a client-authored quiz.

**Credentials:** Shui holds one Shui-WG API key as a Function secret (`WG_API_KEY`,
same `defineSecret` pattern as `R2_SECRETS`/`AI_SECRETS`) — a single account Shui-WG
bills, not a per-learner key. `WG_API_BASE_URL` as a second secret or a plain env var
(not a secret — it's not sensitive) so staging/prod can point at different Shui-WG
deployments.

## 3. Free cap (monetization deliberately deferred)

Every signed-in, non-anonymous learner gets a free monthly allotment of on-demand
lessons — **3 per calendar month** to start (a constant in the new Function, not a
product commitment; make it trivial to change). On `users/{uid}`:

```
onDemandLessonsUsedThisPeriod: number   // default 0
onDemandLessonsPeriodStart: Timestamp   // default account creation; reset when a new call sees a stale period
```

`createOnDemandLesson` checks and increments this **transactionally, before calling
Shui-WG** — never after, so a mid-generation failure doesn't cost the learner their
quota. Roll the period over lazily (if `now` is a new calendar month relative to
`onDemandLessonsPeriodStart`, reset the counter to 0 and bump the period start) rather
than a scheduled Function — simpler, and correct regardless of when a learner is
actually active.

**Do not build unified Shui+Shui-WG membership/billing in this phase.** The free cap is
the whole monetization story here. Structure the cap check as its own small,
named function (e.g. `hasRemainingOnDemandQuota(uid)`) so that when unified membership
arrives later, only that one function's logic changes (e.g. "unlimited if this account
also holds a Shui-WG paid tier") — nothing about how the cap is *read* elsewhere should
need to change.

Guests (anonymous auth) do not get on-demand lessons — `requireNotGuest`, same gate
comments already use for anything that shouldn't be available before a real account
exists.

## 4. The two new callables

### `createOnDemandLesson`
- `requireNotGuest` (not `requireRole` — every real learner, not just creators).
- Input: `{ topic: string (1-300 chars) }`. No other fields — duration, voice, style
  are fixed choices this phase makes on the learner's behalf; do not expose Shui-WG's
  full parameter surface in this first version.
- Transactionally check + increment the free-cap counter (§3). On exhaustion, throw
  `resource-exhausted` with a message the client can show verbatim
  ("You've used all 3 free lessons this month — more come back on the 1st.").
- Ensure `topics/personal-{uid}` exists (`set(..., {merge:true})`, idempotent — same
  discipline `seed_civics.ts` uses), `visibility: "private"`, `createdBy: uid`,
  `categoryId: null` (it's not a real category), a fixed title like "My Lessons".
- Create the `videos/{videoId}` doc immediately with `status: "generating"` (new status
  value — audit every place `status` is switched on, e.g. `videoIsPublic`, the iOS feed
  query, and the creator dashboard, and confirm "generating" is handled or explicitly
  excluded everywhere `"pending"`/`"uploading"` already are), `topicId: "personal-{uid}"`,
  `visibility/topicVisibility: "private"`, `title: <the topic, truncated>`, everything
  else zeroed like a fresh upload shell.
- Call Shui-WG's `POST /v1/videos/generate`, store the returned `job_id` on the video
  doc as `wgJobId`, return `{ videoId }` to the client immediately. **Do not block this
  callable on the render finishing** — Shui-WG renders take well past a comfortable
  callable timeout. Generation happens in the background; the client polls (below).

### `checkOnDemandLessonStatus`
- `requireAuth`, input `{ videoId }`. Loads the video, confirms `createdBy == uid`,
  confirms `status == "generating"` (idempotent no-op if already `ready`/`failed` —
  the client may call this more than once for the same terminal state).
- Calls Shui-WG's `GET /v1/videos/:id` with `wgJobId`.
  - Still queued/rendering: return `{ status: "generating" }`.
  - Failed: update the video to `status: "failed"`, `statusMessage` from Shui-WG's own
    error, return `{ status: "failed", message }`.
  - Ready: run the quiz adapter (§2), write `playbackURL`/`durationSeconds`/
    `sizeBytes` from Shui-WG's response, set `status: "ready"`, `hasQuiz: true`,
    `publishedAt: serverTimestamp()`. Return `{ status: "ready" }`.
- The iOS client polls this every ~3s while showing a generating state — no need for
  a scheduled Function or a Firestore-listener push model for this phase; the AI
  tutor's document-listener streaming pattern is overkill for a single status
  transition that happens once per lesson.

## 5. iOS UI

- A new tab (or a prominent entry point off an existing tab — product's call, not an
  engineering one; if genuinely unsure, add it as its own tab rather than burying it,
  since this is the shareholder's headline feature for this phase) — **"Create."** A
  single text field ("What do you want to learn?"), a generate button, a remaining-
  quota indicator ("2 of 3 free lessons left this month"), and — once generation
  starts — a simple progress state (indeterminate spinner + "Creating your lesson...",
  no fake progress bar since Shui-WG doesn't report granular progress).
- **My Lessons** — a list (grid or vertical list, product's call) of the learner's own
  `videos` where `topicId == "personal-{uid}"`, ordered newest first, each showing
  status (`generating` shows the spinner state inline, `failed` shows a retry
  affordance, `ready` opens playback). This is new UI, but it should be a thin wrapper
  reusing the same `VideoRepository`/feed-cell view code the Explore tab already uses
  for a topic's video list — do not build a second video-list rendering path.
- Tapping a `ready` on-demand video opens the **exact same** full-screen player + quiz
  card flow Phase 2 built. No new playback code, no new quiz-card code.
- Repository layer: extend `VideoRepository` (or add a focused
  `OnDemandLessonRepository` if that reads cleaner — implementer's call) with
  `createLesson(topic:) async throws -> String` (returns videoId) and
  `pollLessonStatus(videoId:) async throws -> LessonStatus`, both thin wrappers over
  the two callables. Views never call Functions directly — same rule as everywhere
  else in this app.

## 6. Verify

1. A learner with 0 prior on-demand lessons this month can create one, watches the
   generating state, and lands on a real, playable video with a real quiz — same feel
   as any curated lesson, including a passing/failing quiz result flowing into
   `topicProgress`/streak/SM-2 exactly as it does for curated content (spot-check the
   Firestore writes match a curated video's submitQuizAttempt run).
2. A 4th attempt within the same calendar month is refused with the exact quota
   message, and the free-cap counter does not increment further.
3. A learner's on-demand lessons never appear in another learner's Explore tab, another
   learner's My Lessons list, or any public/curated query — verified by direct
   Firestore rules test (a failing-path test per the existing emulator-rules-suite
   convention), not just "the UI doesn't show it."
4. A Shui-WG render failure (simulate by pointing `WG_API_BASE_URL` at a server that
   500s) leaves the video in a clear `status: "failed"` state the UI surfaces with a
   retry option, and does **not** refund the free-cap decrement (already spent, since
   §3 requires debiting before the call).
5. Backgrounding the app mid-generation and returning later still resolves correctly —
   `checkOnDemandLessonStatus` is idempotent and safe to call after the app was killed
   and relaunched, not just while the polling loop is continuously running.
6. `git grep` finds no second quiz-writing code path outside `splitQuizForStorage`, and
   no second grading path outside `submitQuizAttempt`.
7. `firestore.rules`'s existing test suite still passes unmodified (proving no rule
   change was actually needed), plus new tests for the "generating" status value
   wherever `status` is rules-checked.
8. `tsc` build, `npm test` (functions unit + rules suite) all green.

## Out of scope

Regenerating or editing an on-demand lesson in place, sharing a personal lesson
publicly or promoting it into a curated topic, multi-video "courses" from one topic
request (always exactly one video per request in this phase), a learner picking voice/
style/length, unified Shui+Shui-WG billing (see §3), comments/likes on personal
lessons (they're private — no audience to like them), any change to
`suggestQuizQuestions` or the creator quiz builder.
