# Phase 7 — Lessons on demand

Read `prompts/README.md` first. Phases 0–5 must be merged. Phase 6 (web dashboard) is
paused by shareholder direction — this phase does not touch it and does not depend on
it. This phase supersedes every earlier draft of Phase 7 built against Shui-WG:
Shui-WG is dead. The vendor is now **GolpoAI** (`https://video.golpoai.com/api-docs`),
a plain video-render API Shui pays per minute, not a sibling product Shui builds.

## Goal

The shareholder direction: Shui is no longer primarily a curated-content feed. A
learner types *any* topic and gets a real, personal lesson — script, quiz, and video —
generated on demand, landing in their own library. Curated Topics still exist but stop
being the thing Shui invests in growing. The new center of the app is:

1. **Create** — "What do you want to learn today?" on login, piping straight into a
   generation pipeline.
2. **My Lessons** (under Profile) — everything a learner has generated.
3. **Social** — a new tab that **replaces Learn** as the primary scroll: other
   learners' *shared* on-demand videos, ranked by reference to what the viewer cares
   about, with a category-chip row and topic search, comments/likes/share reused from
   Phase 3.
4. A **credit-and-tier economy** (four paid tiers plus one lifetime free lesson) that
   makes this financially sustainable against GolpoAI's real $2/minute cost, and a
   **self-serve developer API** that resells the same pipeline outside the app.

GolpoAI is a **render engine, not a curriculum designer** — it has no quiz capability
and, given only a bare topic, produces a generic script. Shui must never hand it a bare
topic. Every generation is: one Claude call writes a pedagogically real script + quiz +
category, GolpoAI renders exactly that script. This is the single most important
architectural decision in this phase — see §2.

## 1. Non-negotiable constraints

Carried forward from every prior phase's discipline, now extended:

- **No second quiz-writing path.** Reuse `QuizInputSchema` and `splitQuizForStorage`
  (`functions/src/schemas/quiz.ts`) exactly as `saveQuiz` does. The one-Claude-call
  adapter (§3) is a new *caller* of these, never a parallel writer.
- **No second grading path.** `submitQuizAttempt` grades an on-demand lesson's quiz
  identically to a curated one. Do not fork it.
- **No second like-counting path.** Tier 3/4's like-refund credit (§5) is an extension
  of the existing `toggleLike` callable's transactional counter update, not a new
  trigger racing against it.
- **No new Firestore rules cascade.** An on-demand lesson is a normal `videos`
  document under a synthetic personal topic (`topics/personal-{uid}`, `isPersonal:
  true`, `categoryId: null`), written by a Cloud Function via the Admin SDK — the same
  privileged-write pattern `createVideoUpload`/`finalizeVideoUpload` already use to
  bypass the client-write-denied rule on `videos`, and the same precedent that
  sidesteps `topics`' `allow create: if isCreator()` restriction (an on-demand lesson
  must be available to any signed-in learner, not only creators). Visibility works
  exactly as Phase 1 already defined it — a video is public only when **both** its own
  `visibility` and its denormalized `topicVisibility` are `"public"`. Sharing a lesson
  to Social (§6) flips the personal topic to `visibility: "public"` once (idempotent)
  and that one video's own `visibility` to `"public"` — every other lesson under the
  same personal topic stays private because its own `visibility` field still gates it.
  **Zero rules changes required** — this is exactly why Phase 1 denormalized both
  fields instead of only checking the parent.
- **Explore/curated Topics must never surface a personal topic.** `isPersonal: true`
  is the explicit filter (do not rely on `categoryId == null` alone being remembered
  everywhere) — audit every place `topics` is queried for a public listing and add it.
- **Money gets a ledger.** Every credit grant, debit, and refund is a row in
  `users/{uid}/creditTransactions/{id}`, never a bare field mutation with no trail —
  this is real money and the shareholder will ask for a reconciliation report.
- **One implementation, two entry points.** The developer API (§8) and the app's own
  callables must share the exact same core functions (`runCreateOnDemandLesson`,
  `runCheckOnDemandLessonStatus`) — same pattern `suggestQuizQuestions.ts` already uses
  (`runSuggestQuizQuestions` exported separately from its `onCall` wrapper). An
  `onRequest` HTTPS function for API-key callers and an `onCall` for the app both wrap
  the same core; the prompt, the GolpoAI call, the cache lookup, and the credit debit
  exist in exactly one place.

This is a different feature from `suggestQuizQuestions` (Phase 5's AI-drafted-questions
button, human-reviewed via `saveQuiz`) — leave that untouched. This pipeline is fully
automatic, no review step, because there's no creator in the loop.

## 2. The GolpoAI contract

REST, `x-api-key` header, async job pattern, no webhooks:

- `POST /api/v2/videos/generate` → `{ job_id, video_id, status: "queued" }` immediately.
- `GET /api/v2/videos/status/{job_id}` → poll until `status` is `completed` or `failed`.

Request Shui actually sends:

```json
{
  "custom_script": "<the full narration Claude wrote — never the bare topic>",
  "timing": "1",
  "video_orientation": "vertical"
}
```

**`custom_script`, never `prompt`.** Handing GolpoAI a bare topic invokes its own
internal prompt-expansion, which reviews consistently describe as generic — it doesn't
know this is lesson content that has to end in an accurate quiz. `custom_script`
guarantees the rendered video says exactly what Shui's own Claude call wrote, and
means the quiz (written from that same script) is always grounded in what actually
plays.

**`timing` is a fixed minute enum** — `"0.25"`, `"0.5"`, `"1"`, `"2"`, `"4"`, `"8"`,
`"10"`, `"15"` (the last requires an Enterprise add-on Shui doesn't have — never
select it). There is no arbitrary duration. Tier durations (§4) are snapped directly to
this enum: **free → `"0.5"`, Siltstone/Obsidian → `"1"`, Alabaster/Pyramidion →
`"2"`.** Do not advertise "1 minute 30 seconds" anywhere in product copy — it doesn't
correspond to a selectable value and would force either wasted render budget or a
silently-truncated script.

**Script Mode's real budget is ~1,050 characters per minute of `timing`.** The Claude
prompt (§3) must be told the exact character ceiling for the request's `timing` value
and instructed to write to it, and the Function must hard-validate the returned
script's length against that ceiling **before** spending the GolpoAI call — a script
that's too long either gets truncated by GolpoAI or rejected; catching it in Shui's own
validation costs fractions of a cent in wasted Claude tokens instead of a wasted $2–4
GolpoAI charge.

**No `custom_logo` at render time.** GolpoAI's `custom_logo`/`logo_position` looked
like the natural watermarking mechanism in the original research, but it doesn't
survive contact with two constraints this phase adds that weren't known then: Tier 3/4
need a *genuinely clean* master (not just "no logo shown in the app," an actual
watermark-free downloadable file), and popular-topic caching (§5) needs **one** render
reused safely across every tier. Baking the logo in at GolpoAI render time makes both
impossible without a second paid render. Instead: **every GolpoAI render is always
clean**, and Shui applies its own watermark as a cheap post-process (§4) only to the
variant served to tiers that require it. This also means a later tier upgrade
retroactively unlocks clean downloads of a learner's *past* lessons for free — the
clean master already exists, it was just never served to them.

**Credentials:** `GOLPO_API_KEY` as a Function secret (`defineSecret`, same pattern as
`AI_API_KEY`/`R2_SECRETS`), one account Shui bills, not per-learner. `GOLPO_API_BASE_URL`
as a plain `defineString` (not sensitive) so staging/prod can point at different bases.

**Real per-minute cost, confirmed:** $1 = 1 credit, 1 minute of video = 2 credits =
$2.00, scaling linearly by the only anchor GolpoAI's docs give (unconfirmed below 1
minute against a per-job minimum floor — verify empirically once real credentials are
available, same caveat as everything else here that needs a live key):

| `timing` | GolpoAI cost | Used by |
|---|---|---|
| `"0.25"` | $0.50 | *(not used in this phase)* |
| `"0.5"` | $1.00 | Free lesson |
| `"1"` | $2.00 | Siltstone, Obsidian |
| `"2"` | $4.00 | Alabaster, Pyramidion |

Every tier charges the learner **$4 per minute** flat (§4) — a consistent 2× markup on
GolpoAI's own linear per-minute cost at every duration, before payment-processor fees
and before bonus credit given away on top-ups/subscriptions, both of which compress the
realized margin — modeled per-tier in §4.

## 3. One Claude call: script, quiz, and category

A single structured call (`functions/src/ai/generateLesson.ts`) produces everything
needed for one lesson, reusing the exact "demand pure JSON, no prose to lose" pattern
already proven reliable in `suggestQuizQuestions.ts` — no streaming, since nothing
renders until the whole draft exists anyway.

**Cost is not a real constraint here.** At Sonnet 5 pricing ($2/$10 per 1M
input/output tokens), one call is on the order of $0.01–0.03 — a rounding error next
to the $1–4 GolpoAI render it produces the script for. Default to `claude-sonnet-5`;
this is not a lever worth optimizing.

Prompt shape:

```
You write a short educational lesson script and a comprehension quiz.

Topic requested: "<learner's raw input>"
Target length: <timing> minute(s) — write narration under <charBudget> characters.
Categories (pick exactly one slug): personal-development, book-summaries, skills,
exam-prep, money-finance, career-business, language-communication, science-tech,
health-fitness, history-culture, creativity-arts

If the topic is unsafe, nonsensical, or not something an educational video can
responsibly cover, respond with {"refused": true, "reason": "..."} and nothing else.

Otherwise respond with JSON only — no prose, no markdown fence:
{
  "categoryId": "<one of the slugs above>",
  "script": "<narration, spoken-style, under the character budget>",
  "quiz": {
    "questions": [
      {"id":"q1","prompt":"...","options":[{"id":"a","text":"..."}, ...],
       "correctOptionIds":["a"],"requiredCorrectCount":1,
       "explanation":"...","orderIndex":0}
    ]
  }
}
```

The refusal branch is the API's content-moderation safeguard (§8) at zero extra cost —
it's the same call, not a second one.

**Adapter, not a new writer:** the `quiz` object is fed straight into
`QuizInputSchema.parse({ videoId, questions: quiz.questions, passThreshold: 0.6 })`,
then `splitQuizForStorage` — identical to how `saveQuiz` writes a human-authored quiz.

**The script becomes the video's `transcript` field**, not a separate field — Phase 1
already defined `transcript` as "creator-provided or auto-generated; feeds the AI
tutor." Writing the Claude-authored script there means Phase 4's AI tutor grounding
works on every on-demand lesson with **zero changes to Phase 4**. Add
`"on_demand_script"` to `transcriptSource`'s existing `"creator" | "auto"` values for
observability.

## 4. Tiers and the credit ledger

Every tier charges lessons at a flat **$4 per rendered minute**, debited from
`creditBalanceCents` (integer cents — never floats for money). The free lesson is a
separate lifetime grant, entirely outside this ledger.

| | Free | Siltstone | Obsidian | Alabaster | Pyramidion |
|---|---|---|---|---|---|
| Cost | — | pay-as-you-go | $20/mo | $50/mo | $200/mo |
| Grant on payment | 1 lesson, once, ever | — | $22.00 credit | $57.50 credit | $240.00 credit |
| Min deposit / top-up | — | $5 | $5 | $5 | $5 |
| Top-up bonus | — | 0% | 10% ($5→$5.50) | 15% ($5→$5.75) | 20% ($5→$6.00) |
| Credit expiry | — | never | never while subscribed | never while subscribed | never while subscribed |
| `timing` | `"0.5"` (30s) | `"1"` | `"1"` | `"2"` | `"2"` |
| Watermark on serve | yes | yes | yes | **no — clean master** | **no — clean master** |
| Downloadable | **no** | yes | yes | yes | yes |
| Like-refund | — | — | — | $2 per video, first time it crosses 100 likes, **capped $20/cycle** | $2 per every cumulative 100 likes across all videos, **capped $20/cycle** |
| Billing cadence | — | none | calendar month | calendar month | balance-triggered (below) |

**Realized margin compresses as tiers rise** — worth showing the shareholder
explicitly when pricing is finalized, since it's the opposite of typical value-based
tiering: Siltstone nets ~$2.00/min (50%), Obsidian ~$1.64/min (45%), Alabaster
~$1.48/min (43%) *before* like-refunds, Pyramidion ~$1.33/min (40%) *before*
like-refunds. Stripe's ~2.9%+$0.30 per charge erodes this further and isn't yet
reflected in any of these numbers. This isn't necessarily wrong — higher tiers may pay
for themselves in usage volume, retention, and Social content supply — but it should be
a deliberate, visible tradeoff, not an accident of the bonus math.

### Watermarking, concretely

GolpoAI always renders clean (§2). Immediately after a render completes
(`checkOnDemandLessonStatus`, §7), a lightweight ffmpeg post-process burns Shui's fixed
top-right logo onto a second copy and uploads both to R2. The video doc stores:

```
playbackURL:            string   // clean master
watermarkedPlaybackURL: string   // Shui's own overlay, generated once per video
```

Which URL is served/downloaded is decided **at access time** by the requesting
learner's *own current tier* (a Siltstone owner who later upgrades to Alabaster
instantly gets clean access to lessons generated before the upgrade — both files
already exist), not baked per-owner at generation time. Run this as a Cloud Run job
rather than a Cloud Function if 2-minute clips push against Function execution/memory
limits — implementer's call, but don't discover the limit in production.

### Billing mechanics

- **Stripe** is the processor. Top-ups are one-off `PaymentIntent`s; Obsidian/Alabaster
  are standard Stripe `Subscription`s billed monthly. On `invoice.paid`, grant that
  tier's credit **additively** on top of whatever remains (a low-usage subscriber's
  balance simply grows every month they don't spend it — flag this to the shareholder
  as a real accumulating liability worth watching, not a bug) and reset
  `likeRefundCentsThisCycle` to 0 for Alabaster.
- **Pyramidion does not use a calendar Stripe subscription at all.** Per the confirmed
  design: track `creditBalanceCents` in Firestore; a scheduled sweep (every 15
  minutes, `onSchedule`, same precedent as Phase 1's `flushViewCounts`/
  `cleanupOrphanedUploads`) finds any Pyramidion account whose balance has dipped below
  $240.00 (24000 cents) and fires an off-session Stripe charge of $200 against the
  stored default payment method, then **adds** 24000 cents on success (never resets —
  a $239 balance becomes $479, matching the confirmed example) and resets
  `likeRefundCentsThisCycle`. Guard with a `pyramidionRechargeInProgress: boolean`
  lock cleared after the charge resolves, so a sweep overlap or a fast double-dip can't
  double-charge. A scheduled sweep is preferable to a live `onDocumentUpdated` trigger
  here — reacting to every write on a hot balance field is noisier and harder to reason
  about than a 15-minute-cadence check for a billing concern with a monthly-scale
  cadence anyway.
- **Debit before render, refund on failure.** `createOnDemandLesson` debits
  `creditBalanceCents` transactionally (balance-check + decrement in one transaction,
  same discipline `rateLimit.ts`'s counter already uses) *before* calling GolpoAI, so
  concurrent requests can't overdraw. Unlike the old free-quota design (where a failed
  generation didn't refund the quota), **a confirmed GolpoAI `failed` status refunds
  the debited credit** — this is real money, and charging a learner for a render that
  never completed is not acceptable. Write both the debit and the refund as
  `creditTransactions` rows (`type: "lesson_debit"` / `"lesson_refund"`).
- **Like-refunds extend `toggleLike`, not a new trigger.** After the transactional
  `likeCount` increment, check the video owner's tier: Alabaster fires once per video
  the first time its `likeCount` crosses 100 (a `refundClaimed: boolean` on the video
  doc prevents re-firing, including if likes later drop below 100 and climb back);
  Pyramidion fires every time the owner's *cumulative* like count across all their
  videos crosses another multiple of 100 (a running counter on `users/{uid}`). Both
  respect `likeRefundCentsThisCycle`'s $20 cap — stop crediting once hit, still record
  the like itself normally.

### Free tier

`hasUsedFreeLesson: boolean` on `users/{uid}`, checked and flipped in the same
transaction as the credit-balance check — if unused, consume it instead of touching
`creditBalanceCents` at all (`timing: "0.5"`, watermarked, non-downloadable, $1.00 real
GolpoAI cost, zero revenue, pure acquisition cost). A second attempt is refused with a
message pointing at Siltstone.

## 5. Popular-topic caching

Confirmed addition: identical or near-identical topic requests should not repeat the
Claude + GolpoAI spend. **v1 scope is exact-normalized-string matching only** — lower-
case, trim, collapse whitespace, strip punctuation, then hash. True semantic
near-duplicate matching (embeddings) is a deliberate fast-follow, not this phase — say
so in the UI/docs rather than pretending this handles paraphrases, the same honesty
Phase 3 already applied to its own prefix-match search.

`lessonCache/{normalizedTopicHash}`: `{ canonicalTopic, sourceVideoId, categoryId,
timing, createdAt, hitCount }`, written the first time any topic is generated
(regardless of tier or origin — app or developer API, §8 — since this is a pure cost
optimization, not a Social-visibility decision).

On a cache hit, `createOnDemandLesson` **skips Claude and GolpoAI entirely**: it
creates a normal owned `videos/{videoId}` doc for the requester (so "My Lessons" stays
one simple query, never a union of owned + referenced content), copying
`playbackURL`/`watermarkedPlaybackURL`/`durationSeconds`/`sizeBytes`/`transcript`/quiz
straight from the cached source, sets `status: "ready"` immediately (no polling — it's
a Firestore write, not a render), and stamps `generatedFromCache: true` +
`cacheSourceVideoId`. This costs nothing regardless of the requester's tier or duration
cap — a Siltstone learner can land a cached 2-minute Alabaster-originated lesson at no
extra render cost; their own tier's watermark-vs-clean serving rule still applies to
*them* independently, since that's decided at access time (§4), not baked into the
cached asset.

**Known v1 limitation, accepted rather than solved now:** if multiple learners each
independently share their own cached copy to Social, the same content can appear as
several distinct rows instead of one canonical video accumulating all the engagement.
Deduplicating Social by underlying content is a reasonable fast-follow once there's
real usage data to justify the complexity.

Caching directly solves the new Social tab's cold-start problem too — see §6.

## 6. Social tab

**Replaces Learn as the primary scrolling tab** (confirmed). `enum RootTab` in
`AppState.swift` currently has `learn, explore, profile, debug` — rename or replace
the `learn` case; audit every switch over it (the root pager, any deep link, any
analytics event named around it).

- **Feed**: public on-demand videos only — `videos` where `visibility == "public"`,
  `topicVisibility == "public"`, `isDeleted == false`, `generationSource ==
  "on_demand"`, `originatedFromApi == false` (API-generated content is never
  Social-eligible — confirmed; it's cache-eligible for cost savings but excluded from
  every user-facing surface outside the developer's own product). Curated content
  stays in Explore, which this phase de-emphasizes but does not remove.
- **Ranking — "based on reference," not random, v1 implementable without ML infra:**
  1. A Function-maintained `socialScore` per video (recomputed on the existing
     like/comment/view-count write paths, same denormalized-counter discipline as
     `masteryPercent`): `log(1+likeCount)*2 + log(1+commentCount) + log(1+viewCount)*0.5`
     minus a simple age-decay term.
  2. At query time, two-pass: first page from videos whose `categoryId` is in the
     viewer's own `users/{uid}.interests` (already collected at onboarding, already
     drives Explore ordering — this reuses that exact signal), ordered by
     `socialScore desc`; backfill with the general `socialScore desc` query once the
     interest-scoped page runs thin. This is the concrete shape of "ranked by
     reference, not fully random" — an affinity-first, popularity-fallback feed, not a
     live learned ranker.
  3. **Caching (§5) is the Social cold-start fix**: pre-generate ~20–50 lessons across
     popular topics on Shui's own budget before launch (using the app path, then
     `shareLessonToSocial`), so the feed and the category chips aren't empty on day
     one, and every subsequent duplicate request reinforces the same cached asset's
     score instead of costing another render.
- **Category chips**: the same 11 fixed slugs, filtering the feed to one category —
  "select a category... like TikTok search."
- **Search**: same honesty as Phase 3's topic search — client-side prefix match over
  cached video `title`s, not real full-text search. Note it as the same Algolia/
  Typesense follow-up Phase 3 already flagged; don't build a second, inconsistent
  search story.
- **Comment/like/share**: reuse Phase 3's comment sheet and `toggleLike` verbatim — no
  new social primitives, only a new content source feeding the existing ones.

## 7. The two on-demand callables (app-facing)

### `createOnDemandLesson`
`requireNotGuest`. Input `{ topic: string (1–300 chars) }`.
1. Normalize + hash the topic; on a `lessonCache` hit, return the copied-cache result
   (§5) immediately — no further steps.
2. Otherwise: check `hasUsedFreeLesson` (§4) or transactionally debit
   `creditBalanceCents` for the caller's tier's `timing`×$4 (insufficient balance →
   `resource-exhausted` with a message the client shows verbatim, pointing at top-up).
3. Ensure `topics/personal-{uid}` exists (idempotent `set(..., {merge:true})`,
   `isPersonal: true`, `visibility: "private"`, `categoryId: null`).
4. Run the Claude call (§3). A `{"refused": true}` response ends here with no charge —
   refund whatever was just debited, return a typed error the UI shows as "that topic
   isn't something we can make a lesson for."
5. Validate the returned script against the `timing` character budget (§2/§3).
6. Create `videos/{videoId}` with `status: "generating"`, `topicId:
   "personal-{uid}"`, `visibility/topicVisibility: "private"`, `generationSource:
   "on_demand"`, `originatedFromApi: false`, `categoryId` from Claude's classification,
   `transcript`/`transcriptSource: "on_demand_script"`, `tierAtGeneration`,
   `costChargedCents`.
7. Call GolpoAI `POST /api/v2/videos/generate` with `custom_script`, store the
   returned `job_id` as `golpoJobId`. **Do not block on the render** — return
   `{ videoId }` immediately; the client polls.

### `checkOnDemandLessonStatus`
`requireAuth`, input `{ videoId }`, owner-only, idempotent on an already-terminal
status.
- Polls GolpoAI `GET /api/v2/videos/status/{job_id}`.
- `failed` → `status: "failed"`, refund the debited credit (§4), return the message.
- `completed` → write the quiz adapter (§3), run the watermark post-process (§4)
  writing both `playbackURL`/`watermarkedPlaybackURL`, write to `lessonCache` if this
  was the first generation of this normalized topic, set `status: "ready"`, `hasQuiz:
  true`, `publishedAt`.
- Client polls every ~3s; no scheduled Function or push model needed for a single
  status transition per lesson.

### `shareLessonToSocial`
`requireAuth`, input `{ videoId }`, owner-only, `status == "ready"` only. Flips
`topics/personal-{uid}.visibility` to `"public"` (idempotent, only matters the first
time) and this one video's `visibility` to `"public"`, sets `sharedToSocial: true`,
`sharedAt`. Every other lesson under the same personal topic is unaffected — see §1 for
why this needs no rules change.

## 8. Developer API

Self-serve (confirmed): any account can mint a key from account settings and generate
lessons programmatically against their **own** credit balance and **own** current
tier's `timing`/watermark rules — Tier 1/Siltstone is the natural entry point for
someone testing the product, not a hard technical gate; a Pyramidion account's key
still works, still charged and rendered per their own tier. Output never touches Social
or another user's view (§6) — it's a developer integration surface, isolated from the
consumer app's social graph, though it **does** participate in the shared cache (§5)
for cost savings.

- `apiKeys/{keyId}`: `{ uid, keyHash (SHA-256, never store the raw key), label,
  createdAt, lastUsedAt, revoked, requestCount }`. Raw key (`shui_live_...`) shown once
  at creation via `createApiKey` (`requireNotGuest`); `revokeApiKey` flips `revoked`.
- `POST /v1/lessons` and `GET /v1/lessons/{id}` — plain `onRequest` HTTPS functions,
  `x-api-key` header resolved to a `uid` via the hashed lookup, wrapping the exact same
  `runCreateOnDemandLesson`/`runCheckOnDemandLessonStatus` core the app callables use
  (§1's "one implementation, two entry points"). No Firebase Auth token involved on
  this path.
- **Safeguards**: the credit pre-debit transaction (shared with the app path) is
  already the primary abuse brake — a leaked key can't spend money that isn't in the
  account. On top of that: a per-key rate limit (reuse the `rateLimit.ts` shape, a
  coarser bucket than the AI tutor's — e.g. 20 requests/hour — as a circuit breaker
  against a compromised key being hammered faster than a human would notice) and the
  same-call content-moderation refusal already built into the Claude prompt (§3) —
  there's no app UI in front of this surface to catch an obviously bad topic
  otherwise.
- **Documentation**: a versioned reference (auth header, request/response JSON, error
  codes, rate limits, the $4/min pricing) living alongside the Functions code so it
  can't drift from the real implementation — mirror GolpoAI's own docs structure
  loosely, since that's the shape a developer integrating both will already expect.

## 9. iOS UI

- **Create** — the first-screen entry point on login: "What do you want to learn
  today?", a single text field, a generate button, and (for non-free-eligible users) a
  visible credit balance / top-up prompt. Once generation starts: an indeterminate
  spinner + "Creating your lesson..." — GolpoAI reports no granular progress, don't
  fake one.
- **My Lessons** (under Profile, replacing/absorbing the old Profile structure's
  emphasis) — `videos` where `topicId == "personal-{uid}"`, newest first, each showing
  its status inline (`generating` spinner, `failed` with retry, `ready` opens
  playback). A `ready`, unshared lesson shows a **Share to Social** action. Reuse the
  same feed-cell/list rendering code Explore already uses for a topic's video list — no
  second video-list view.
- **Social** — the new tab (§6): category chips, search field, comment/like/share
  reused from Phase 3.
- **Tier / billing screen** — reachable from Profile settings: current tier, credit
  balance, top-up, subscribe/change tier, transaction history (reading
  `creditTransactions` — never letting the client compute a balance itself, only
  display the server-maintained `creditBalanceCents`).
- Tapping any `ready` on-demand video, owned or from Social, opens the **exact same**
  full-screen player + quiz card flow Phase 2 built. No new playback or quiz-card code.
- Repository layer: `OnDemandLessonRepository` (`createLesson(topic:)`,
  `pollLessonStatus(videoId:)`, `shareLessonToSocial(videoId:)`) and a
  `BillingRepository` (`balance()`, `createTopUpIntent(amountCents:)`,
  `subscribe(tier:)`), both thin wrappers over the callables above — views never call
  Functions directly, same rule as everywhere else in this app.

## 10. Verify

1. A fresh account's first-ever generation is free, 30 seconds, watermarked,
   non-downloadable, debits nothing, and flips `hasUsedFreeLesson`; a second attempt is
   refused with the exact message and Siltstone points forward correctly.
2. Siltstone: deposit $5 → balance 500¢; generate a `timing:"1"` lesson → balance
   400¢, `costChargedCents` recorded, a `lesson_debit` ledger row exists, video is
   watermarked-served and downloadable.
3. Obsidian/Alabaster: subscribing grants the bonus-adjusted credit exactly (test-mode
   Stripe), a top-up applies the correct tier bonus, canceling stops future grants
   without retroactively removing already-granted balance.
4. Alabaster: a video crossing 100 likes (set directly in the emulator) posts exactly
   one $2 refund; crossing again on the same video posts nothing further; refunds
   across several videos in one cycle stop at the $20 cap; the served master has no
   watermark and is downloadable.
5. Pyramidion: manually drop a test account's balance below 24000¢ in the emulator,
   run the sweep, confirm an off-session charge fires, balance is credited
   **additively** (matches the $239→$479 example), the recharge-in-progress lock
   prevents a double-fire, and cumulative-100-like refunds (not one-time-per-video)
   respect the same $20 cap.
6. A GolpoAI `failed` status refunds the exact amount debited, with a matching
   `lesson_refund` ledger row.
7. Requesting the same normalized topic twice from two different accounts: the second
   request makes **zero** calls to the Claude/GolpoAI clients (assert against a
   mock/spy), resolves to `ready` instantly, and each account has its own private
   `videos` doc.
8. An unshared lesson never appears in another account's Social feed, Explore, or any
   public query — verified by a direct Firestore rules test, not just "the UI doesn't
   show it." After `shareLessonToSocial`, it does, and every other lesson under the
   same personal topic is still private.
9. Social ranking: given two same-category videos with different engagement, the
   higher-`socialScore` one ranks first for a viewer with no matching interest; a
   viewer whose `interests` include that category sees it ahead of a higher-scored
   video outside their interests.
10. Developer API: `createApiKey` returns a raw key shown once; a REST call with a
    valid key succeeds and debits the key owner's balance exactly as the app path
    would; a revoked or malformed key is rejected; exceeding the per-key rate limit is
    refused; an API-generated video never appears in Social, Explore, or any other
    account's view, but *is* eligible for the shared cache.
11. `firestore.rules` denies a client writing `creditBalanceCents`, `apiKeys/*`, or
    another user's `creditTransactions` directly — Functions only, verified by a
    failing-path test per path.
12. `git grep` finds exactly one quiz-writing path, one grading path, one
    like-counting path (`toggleLike`), and no duplicated Claude-prompt or GolpoAI-call
    logic between the app callables and the API's `onRequest` handlers.
13. `tsc` build, `npm test` (functions unit + rules suite) all green.

## Out of scope

Semantic/embedding-based near-duplicate cache matching (v1 is exact-normalized-string
only), unsharing a lesson back to private, editing a generated script in place
(regeneration is always a full new charge), multi-video "courses" from one request,
learner-selectable voice/style, a moderation queue beyond the single-call refusal check,
deduplicating Social when multiple learners share their own cached copies of the same
underlying content, any change to `suggestQuizQuestions` or the creator quiz builder,
anything in Phase 6 (paused).
