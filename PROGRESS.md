# Shui — Build Progress & Decision Log

A running record of what's been built, why, and what broke along the way. The
phase plan itself lives in [`prompts/README.md`](prompts/README.md); this file
is the narrative of actually executing it — read it if you're picking the
project back up and want context faster than re-reading every commit.

Updated as each phase progresses. Current state: **Phases 0–5 done and
live-verified on a real device** — foundation, backend, the video feed,
discovery/social (Explore, Profile, Comments), the AI tutor, and in-app
creator mode are all built, pushed, and have each been through at least
one real round of "user tests on a physical build, reports an actual bug,
it gets root-caused and fixed" — not just static review. A long tail of
post-Phase-5 enhancement work (Save videos, Explore/Profile navigation
redesign, swipe-to-navigate, several real bug fixes) is layered on top of
Phase 5's own section below, since it was scoped and built incrementally
in response to live feedback rather than as its own numbered phase.

**Phase 6 (browser dashboard) is paused by shareholder direction — not
resuming until Phase 7 ships.** The shareholder pivot: Shui moves from a
purely curated feed to lessons-on-demand, backed by the third-party
GolpoAI render API instead of an in-house whiteboard-video product, with
a four-tier credit economy and a new Social tab replacing Learn. See
`prompts/phase-07-lessons-on-demand.md`.

**Phase 7 backend (Slices 1–6) and iOS (Slice 7) are both built and
pushed** — every callable, the Apple IAP billing path, the tier-aware AI
tutor, the Social ranking trigger, the developer API, and every iOS
screen phase-07 §9 calls for. Backend is verified the same way every
phase since 1 has been (`tsc`, the full unit suite, the rules suite
against the real Firestore emulator). The iOS half is checked by hand
only, same limitation as every Swift phase before it (see Phase 6's own
note on this) — same standing next step as every phase, too: `git pull`,
`xcodegen generate`.

## Phase status

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: strip the dead lesson engine, English-only, Firebase SDK, clean build | ✅ Done |
| 1 | Firestore model, security rules, Cloud Functions, R2 upload pipeline, seed content | ✅ Done — verified end-to-end on the real `shui-prod` project |
| 2 | Vertical video feed + end-of-video quiz + playback | ✅ Done — verified end-to-end on the real `shui-prod` project |
| 3 | Categories, topic pages, auth, profile, progress, likes, comments | ✅ Done — backend verified against the emulator; live-tested on a real device across multiple rounds (Explore, Profile, Comments, search, likes), real bugs found and fixed |
| 4 | AI tutor: grounded chat + proactive retention checks | ✅ Done — backend verified (`tsc`, unit tests, eval harness smoke-tested — no live model credentials in this sandbox, so no real eval scores); live-tested on a real device, including a real paging regression found and fixed |
| 5 | In-app creator console: topics, uploads, quiz builder, publish controls | ✅ Done — backend verified (`tsc`, rules emulator, composite indexes declared up front); live-tested extensively on a real device across many rounds (topic editor, upload flow, quiz builder, publish gates, admin surface, role claims), each round's real bugs found and fixed. Substantial enhancement work built on top after the phase itself closed out — see that section below for the full list |
| 6 | Browser dashboard for bulk authoring | ⏸️ Paused — scaffold done (6.1); shareholder redirected focus to Phase 7 before auth/role gating and the real screens were built |
| 7 | Lessons on demand: GolpoAI backend, four-tier credit economy, Social tab replacing Learn, self-serve developer API | ✅ Backend and iOS both built — backend verified (`tsc`, unit + rules-emulator suites); iOS checked by hand only, needs `xcodegen generate` (see below). Not yet live-tested: no real GolpoAI/Anthropic/Apple sandbox credentials in this sandbox |

---

## Phase 0 — Foundation

Stripped everything left over from the app's previous identity (a bundled-content
Vietnamese citizenship tutor) down to a compiling, honest shell: three placeholder
tabs, the Firebase SDK wired up but unconfigured beyond `FirebaseApp.configure()`,
English-only, no simulated auth or fake subscription tiers left in to be mistaken
for real ones.

Verified by the user in real Xcode: clean build, all unit tests passing,
`FirebaseBootstrap` confirming it connects to the right project.

Real bugs hit and fixed during that verification pass:
- Missing `import SwiftData` in `ShuiApp.swift` — `.modelContainer(_:)` wasn't
  visible to the compiler without it.
- XcodeGen's package requirement syntax: `minVersion` needs a paired `maxVersion`
  to mean a range; `from:` is the correct key for "this version or later."
- `ShuiTests` target was missing `GENERATE_INFOPLIST_FILE: YES` in `project.yml`,
  so running tests (the first time anyone ever had) failed code signing.

## Phase 1 — Backend

### What got built

- **Firestore schema** (`prompts/phase-01-backend.md` §1): categories, topics,
  videos, the `quiz/current` vs `quiz/answers` split (prompts+options are public;
  correct answers are owner/admin-only, enforced by security rules — grading
  never happens on-device), users and their subcollections (topicProgress,
  videoProgress with SM-2 state, likes, aiUsage), comments, reports, viewEvents.
- **`firestore.rules`** — deny-by-default, one row per collection, a rules test
  suite (`functions/test/rules.test.ts`) with **65 cases** run against a real
  Firestore emulator: a positive and a negative case for every row.
- **Cloud Functions** (`functions/`, TypeScript, 2nd gen, `us-central1`) — 14
  callables (`createVideoUpload`, `finalizeVideoUpload`, `createThumbnailUpload`,
  `saveQuiz`, `submitQuizAttempt`, `markVideoCompleted`, `toggleLike`,
  `setTopicVisibility`, `setVideoVisibility`, `softDeleteTopic/Video/Comment`,
  `claimHandle`, `assignRole`) and 4 triggers (`onCommentWritten`, `onUserCreated`,
  and two scheduled jobs — `cleanupOrphanedUploads`, `flushViewCounts`). SM-2
  scheduling ported verbatim from `SpacedRepetitionScheduler.swift` into
  `functions/src/lib/sm2.ts`, with a parity test asserting both implementations
  agree. 25 unit tests total (SM-2, the mastery formula, streak math, quiz schema
  validation).
- **R2 upload pipeline** — presigned PUT URLs minted server-side via
  `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`; the client PUTs
  directly to R2, Firebase never touches the video bytes.
- **Swift repository layer** (`Shui/Sources/Data/`) — 9 repositories (Category,
  Topic, Video, Quiz, Progress, Social, User, Upload, and a protocol-only
  AITutor for Phase 4), each as protocol + live Firestore/Functions
  implementation + in-memory fake, held by one `AppEnvironment` injected at the
  root. Codable models mirror the Firestore schema with defensive decoding — a
  malformed document drops out of a page instead of crashing the fetch.
  `Sources/Data/` (plus `FirebaseBootstrap.swift`) is the only place allowed to
  import Firebase; enforced by `git grep "import Firebase"`.
- **Seed scripts** (`scripts/`, its own standalone `package.json`) —
  `seed_civics.ts` seeds the 11 fixed categories and one real topic (the
  official 2025 USCIS civics test, 128 questions, grouped into quiz-sized
  chunks), idempotent, skips the 8 questions whose answers depend on who
  currently holds an office or which state the learner lives in.
  `bootstrap-admin.ts` grants the first admin claim, breaking the
  chicken-and-egg problem where `assignRole` itself requires an admin caller.
- **Debug-only upload screen** (`Sources/Views/Debug/DebugUploadPipelineView.swift`,
  `#if DEBUG`) — the one sanctioned piece of UI this phase, proving the whole
  pipeline works: sign in / create account → create a test topic → pick a local
  video → `createVideoUpload` → PUT to R2 → `finalizeVideoUpload` → plays back
  in `AVPlayer`. Gets deleted or replaced once Phase 2 has a real upload flow.

### Verification

Self-verified in the build sandbox (no Xcode there, but Node + Java + the
Firebase emulator suite are): 65 rules tests, 25 unit tests, clean `tsc`,
`seed_civics.ts` run twice against the emulator with identical output
(idempotency confirmed).

Then verified for real, on the user's Mac, against the actual deployed
`shui-prod` project — including a real device upload through the full
pipeline. Confirmed working end to end on **2026-07-31**: a real video file
picked from Files, uploaded through a presigned R2 URL, finalized, and played
back from `https://pub-29f895ffbdcf49779204f67d1a69af9b.r2.dev/...` in
`AVPlayer`.

### Deployment gotchas (read this before touching `functions/` or redeploying)

None of these showed up in emulator testing — they're all real-deploy-only
failure modes, discovered by actually running `firebase deploy` for the first
time on this project. Worth reading before the next real deploy, since some of
these could recur when new functions are added in later phases.

1. **`firebase.json`'s functions `ignore` list included `"lib"`.** The
   predeploy step (`tsc`) correctly builds `functions/lib/` locally, but the
   packaging step that uploads to Cloud Build was told to exclude that exact
   directory — so every function's build failed with `lib/index.js does not
   exist`. Root cause: conflating `.gitignore` (correctly excludes `lib/` from
   version control, since it's a build artifact) with the *separate* deploy-time
   ignore list, which needs the opposite. Fixed by dropping `"lib"` from the
   ignore array.

2. **`.secrets.local.env` (real R2 credentials) was not excluded from the
   deploy upload.** Confirmed against `firebase-tools`' own source: once
   `firebase.json` sets an explicit functions `ignore` list, `.gitignore` is
   never consulted at all for deploy packaging — only that explicit list
   matters. The list only excluded `*.local`, not `*.env` files, so the real
   secrets file was very likely uploaded to Cloud Build during the failed
   deploy attempts above. Fixed by adding `*.local.env` to the ignore list.
   **Precaution taken:** the R2 API token was rotated afterward.

3. **Cloud Functions 2nd gen requires the Blaze (pay-as-you-go) plan.** The
   free Spark plan can't enable Secret Manager or deploy 2nd-gen functions at
   all. One-time project-level upgrade; free tier covers dev/test usage.

4. **The Firestore database itself was never created.** A Firebase project
   doesn't provision one automatically. Created manually via Console
   (Firestore Database → Create database → Production mode →
   `us-central1`) — must use the literal database id `(default)`, since
   nothing in this codebase (Admin SDK, client SDK) ever references a
   non-default database.

5. **`firestore.indexes.json` had an invalid single-field composite index**
   for `videoProgress.dueDate`. Firestore rejects composite indexes that only
   cover one field ("this index is not necessary, configure using single
   field index controls") — automatic per-field indexing already serves that
   query (`dueForReview` filters and orders by the same field, `dueDate`).
   Copied from the phase doc's suggested list without checking it against the
   actual query shape. Removed.

6. **New Cloud Run-backed callables weren't publicly invokable on first
   deploy** — every callable failed with `UNAUTHENTICATED` from the app, but
   Firestore rules-based writes worked fine, which was the tell: the rejection
   was happening at the Cloud Run/IAM layer, before the request ever reached
   application code (confirmed via `firebase functions:log`, which showed
   `The request was not authorized to invoke this service. The access token
   could not be verified.` — an infra-level message, not one of ours).
   Firebase is supposed to automatically grant public invoke access to
   callable functions at deploy time; that grant didn't take on this
   project's first 2nd-gen deploy. Fixed manually, once, via:
   ```sh
   gcloud functions add-invoker-policy-binding FUNCTION_NAME --region=us-central1 --member=allUsers
   ```
   applied to each of the 14 client-facing callables (not the 4
   trigger/scheduled functions, which are invoked by Google's own services and
   shouldn't be made publicly invokable). **If a brand-new callable added in a
   later phase gets `UNAUTHENTICATED` on its very first deploy, this is almost
   certainly why — check `firebase functions:log --only <name>` for that exact
   message before assuming it's an application bug.**

7. Two smaller ones, low-stakes: `HTTPSCallableResult.data` is a non-optional
   `Any` in the Swift SDK, not `Any?` — a `guard let` on it fails to compile.
   And macOS ships bash 3.2 (2007) as `/bin/bash`, whose parser can misread a
   variable name butted directly against a multi-byte Unicode character with
   no separator — caused an `unbound variable` crash in
   `functions/scripts/set-r2-secrets.sh` from a bare `$name…`. Fixed by bracing
   variables and sticking to plain ASCII in shell scripts going forward.

## Phase 2 — Feed

### What got built

The Learn tab: a full-screen, TikTok-style vertical video feed that ends
every video in a server-graded quiz.

- **`FeedPlayerPool`** (`Sources/Playback/FeedPlayerPool.swift`) — replaces
  the old `VideoPlaybackController`. A fixed ring of 4 pooled `AVPlayer`
  instances keyed by feed index (not video id), so scrolling never
  allocates or tears down a player mid-scroll. Handles prepare / activate /
  recycle / restart, KVO on item status and `isPlaybackLikelyToKeepUp`,
  end-of-item notification, a periodic progress observer, and
  `AVAudioSession` interruption handling (phone call interrupts playback,
  resumes after if the system says it can).
- **`FeedComposer`** (`Sources/Feed/FeedComposer.swift`) — the ordering
  algorithm, a pure function with no repository or network access (unit
  tested directly). Interleaves four buckets — due-for-review,
  continue-topic, new-in-interests, everything-else — in that priority
  order, but caps review items at 3 in a row and 4 per any 10-item window
  so reviews never dominate the session. Falls back to a plain review run
  only once every other bucket is exhausted. Dedups both within one call
  and across pagination batches via an `alreadyPlaced` parameter.
- **`FeedPageViewModel`** (`Sources/Feed/FeedPageViewModel.swift`) — one
  instance per video, owns the post-playback state machine:
  `notEnded → (loadingQuiz →) answering → submitting → (submissionFailed |
  revealing → result)`. Answers are collected locally per question and
  submitted once, at the end, in a single call — grading is entirely
  server-side, this client never sees a correct answer ahead of time.
- **`FeedViewModel`** (`Sources/Feed/FeedViewModel.swift`) — orchestrates
  everything above: pagination (mixed feed via `FeedComposer`, or a single
  topic's videos), prefetch/recycle against the player pool, view tracking
  (`viewEvents` + `markVideoCompleted`), like toggling, quiz submission,
  and a mastery-delta computation (diffs `topicProgress` before/after
  submit — the callable doesn't return this, so it's computed client-side).
- **Offline quiz-attempt queue** — `PendingQuizAttempt` (SwiftData model,
  answers round-tripped through JSON since SwiftData can't store
  `[QuizAttemptAnswer]` directly), new `PersistenceController` queue
  methods, and `NetworkMonitor` (`NWPathMonitor`-backed) triggering a flush
  the moment connectivity returns. A failed submission stays queued and
  retryable rather than silently dropped.
- **View layer** (`Sources/Views/Feed/`) — `FeedView` (the paging
  container, iOS 17 `ScrollView`/`LazyVStack`/`.scrollTargetBehavior(.paging)`),
  `FeedPageView` (one full-bleed page: video + status overlay + gradient
  scrim + progress bar + caption + right rail + tap-to-pause),
  `QuizCardView` (the slide-up overlay covering every state in the quiz
  machine), `FeedRightRail` (like / comments-placeholder / AI-placeholder /
  share, guest actions routed to a sign-in stub sheet), `FeedSheets`
  (video info, "coming soon" placeholders, sign-in stub), and
  `FeedEmptyStateView` (covers both "nothing published" and "caught up"
  with one adaptive view — the composer's due-item guarantee means an
  empty feed with a nonzero review count can't actually happen).
- Accessibility: Dynamic Type support (video caption capped at `.xLarge`,
  quiz card uncapped per the phase spec), `accessibilityLabel`/`Value`
  throughout the rail and quiz options, `@Environment(\.accessibilityReduceMotion)`
  swapping the quiz card's slide transition for a cross-fade.
- **Explicitly out of scope this phase** (per `prompts/phase-02-feed.md`):
  real comments, the real AI tutor, categories/Explore, profile, creator
  tools, real sign-in. All represented by placeholder sheets/tabs that name
  the phase they land in.

### An architectural fix made along the way

`Page<T>.cursor` was `DocumentSnapshot?` — a Firebase type — which the new
feed pagination code would have had to touch outside `Sources/Data/`,
breaking the "Firebase imports confined to `Sources/Data/` +
`FirebaseBootstrap.swift`" rule from Phase 1. Caught before any view code
was written against it. Fixed by introducing an opaque `PageCursor` wrapper
(`Sources/Data/FirestoreSupport.swift`) that holds the snapshot without
exposing it — callers outside `Sources/Data/` can hold and pass one back
without ever importing Firebase themselves.

### Verification

**No Swift compiler exists in this sandbox** (unlike Phase 1, which had
Node + the Firebase emulator suite to self-verify against). Everything
here was checked by hand instead:

- Brace/paren balance counted per file — all balanced.
- A repo-wide grep for duplicate top-level type names — specifically
  re-checking for the exact bug class (`QuizOption` redeclared) that broke
  the Phase 1 build. None found.
- `import Firebase` confinement re-verified — still only `Sources/Data/`
  and `FirebaseBootstrap.swift` (plus the new `AppAnalytics.swift`, itself
  under `Sources/Data/`).
- No stray `DocumentSnapshot` reference outside `Sources/Data/`.
- Every repository/model call site in the new code cross-referenced by
  hand against the actual Phase 1 declarations (`Video`, `Quiz`,
  `QuizQuestion`, `QuizOption`, `QuizResult`, `QuizQuestionResult`,
  `TopicProgress`, `VideoProgress`, `UserAccount`) to catch signature
  mismatches before a real build would.
- Two new test suites written to satisfy the phase's own verify checklist:
  `FeedComposerTests` (8 tests: review-first ordering, the two spacing
  caps, the review-run fallback, dedup within and across batches,
  deterministic ordering, priority fallthrough) and
  `FeedPageViewModelTests` (12 tests: the no-quiz path, the quiz-still-
  loading race, single/multi-select toggling, `canAdvance` gating, full
  answer collection through submission, the reveal walk-through, retry
  after a failed submission, and `replay()`'s full state reset).

None of this substitutes for a real build. Real compiler errors are
expected here, same as Phase 1 surfaced two the emulator/self-review pass
couldn't have caught (`QuizOption` redeclaration, `HTTPSCallableResult.data`
being non-optional).

### Real-world debugging (after the first build)

Phase 2 built and ran cleanly (no compiler errors this time), but the Learn
tab showed "Nothing here yet" against the real deployed backend. Chasing
that down surfaced several real gaps, same pattern as Phase 1's deployment
gotchas — things no amount of self-review in this sandbox could have caught:

1. **There was genuinely no path to a public video.** `seed_civics.ts`
   creates its topic `private` (publishing is a Phase 5 feature), and
   `createVideoUpload` always starts a video `private` regardless of its
   topic. "Nothing here yet" was the correct response to zero public
   content, not a bug — but there was no way to *get* a public video for
   testing without Phase 5's creator console. Fixed by adding a
   `VideoRepository.setVisibility` and `QuizRepository.saveQuiz`, and a
   "4. Attach a quiz and publish" step to the debug pipeline screen
   (`saveQuiz` → `setVideoVisibility` → `setTopicVisibility`, in that order,
   since each precondition depends on the last).
2. **The feed never re-fetched after its first load.** `FeedView` only
   fetched via `.task`, which fires once per view identity — and `TabView`
   keeps every tab's content alive across switches, so publishing a video
   from the Debug tab and flipping back to Learn showed the same stale
   empty result. Fixed with `FeedViewModel.refresh()` (full pagination +
   player-pool reset) wired up as standard pull-to-refresh — this is normal
   feed UX regardless, not just a debug workaround.
3. **A failed fetch and a genuinely empty feed looked identical.**
   `loadError` was already being captured but nothing displayed it, so a
   real failure silently rendered as "Nothing here yet" — indistinguishable
   from there just being no content. Fixed with a distinct
   `FeedErrorStateView`. This is what finally surfaced gotcha #4 instead of
   another round of guessing.
4. **`videos(inTopic:)` was missing a composite index.** It filters on
   `topicId`, `status`, and `isDeleted` and orders by `order`, but
   `firestore.indexes.json` only had `{topicId, order}` — a leftover from
   before the status/isDeleted filters were added. The Firestore emulator
   doesn't enforce composite index requirements the way production does,
   so Phase 1's emulator-based self-testing never would have caught this
   either. Once surfaced (via gotcha #3's error screen — Firestore's own
   error message includes a direct link to create the missing index),
   audited every query in `Sources/Data/` and `functions/src/` against
   `firestore.indexes.json` rather than patching just this one: fixed the
   `videos(inTopic:)` index and proactively added one for
   `CategoryRepository.list()` (`{isActive, sortOrder}` — not yet called by
   any Phase 2 view, but the same missing-composite-index shape, and it
   will be the moment Phase 3's Explore tab lists categories). Every other
   query in both the Swift and Functions code was confirmed to either need
   no composite index (pure equality filters with no `orderBy`, or a single
   range/equality filter ordered by that same field) or already have a
   matching one.

**Requires `firebase deploy --only firestore` before this next build will
show real content** — this is an index-definition change, not app code.

### Confirmed working end to end

Verified live on **2026-07-31** against the real `shui-prod` backend, after
the index deploy: a published video plays full-screen, the end-of-video
quiz card appears and works, and — once a second video was published
through the debug flow — swiping up transitions cleanly to the next video,
confirming the pooled-player paging behavior (`FeedPlayerPool` activating
the new slot and pausing the old one) works as designed, not just in
isolated unit tests.

## Phase 3 — Discovery, identity, and the social layer

### A design-system rewrite first, deliberately out of the phase's own scope

Before touching any Phase 3 screen, rebuilt the color system from scratch —
the user explicitly asked for semantic naming, verified WCAG AA contrast in
both light and dark, and a structure that could take on more themes later
without a refactor. Given Phase 3 was about to add a large amount of new
UI (auth, onboarding, Explore, Profile, Comments), doing this first and
building every new screen on top of it was the only way to avoid doing
that UI twice.

- **`ThemePalette`** (`Sources/Theme/ThemePalette.swift`) — a protocol of
  semantic roles (`canvas`, `surface`, `textPrimary`, `textOnAccent`,
  `accent`, `border`, `success`/`warning`/`error`/`info`, `scrim`, …), never
  a raw hex value at a call site.
- **`LightPalette`/`DarkPalette`** — the two concrete themes, resolved from
  the system color scheme via `.shuiTheme()` at the app root and read
  anywhere via `@Environment(\.theme)`. Every literal color in both was
  computed with the actual WCAG relative-luminance formula (not eyeballed)
  before being written down — see `ShuiTests/ThemeContrastTests.swift`,
  which re-derives the same math in Swift and checks every real
  foreground/background pairing the app draws, including every point along
  the 3-stop accent gradient, not just its stops. That verification caught
  two real, already-shipped accessibility bugs in the old Phase 0/1
  palette: metadata text at 4.35:1 on the canvas background (needs 4.5:1),
  and white button labels on the gradient's lighter stops as low as 1.5:1.
  Both fixed in the new palette; a theme added later is checked by the
  same test suite automatically, since it iterates `AppTheme.allCases`.
- Migrated every existing `Theme.shell.*` call site to the new tokens,
  including `QuizCardView`'s correct/incorrect feedback, which had been
  using unverified system `.green`/`.red` directly.

### What got built

- **Real authentication** (`AuthRepository`, `AppleNonce`,
  `SignInSheet.swift`) — guest-first: anonymous sign-in at launch,
  browsing/watching/quizzing all work with no account. Sign in with Apple
  via SwiftUI's native `SignInWithAppleButton` (draws the actual required
  HIG button); email sign-up/sign-in unified into one
  `continueWithEmail()` call that links first and falls back to a plain
  sign-in on `emailAlreadyInUse`, matching the spec's "sign-up / sign-in
  detection" from a single form. Upgrading a guest links the new
  credential to the existing anonymous uid in place, so progress/likes/
  quiz history carry over with no migration step; landing on a
  pre-existing account instead (`credentialAlreadyInUse` /
  `emailAlreadyInUse`) shows an explicit "your guest progress didn't
  transfer" notice rather than staying silent about it. A first real
  sign-in (empty handle, the reliable "never claimed one" signal) prompts
  for a display name and handle via `claimHandle`.
- **`deleteAccount`** (new Cloud Function, task the phase needed that
  Phase 1's callable list didn't include) — anonymizes comments
  (`authorName` → "Deleted user", thread kept intact for replies), removes
  progress/likes subcollections, releases the claimed handle, soft-deletes
  the user doc (new `isDeleted` field, Function-only like `role`/`handle`),
  deletes the Auth user last so a failure partway through never orphans an
  Auth account with no Firestore trace.
- **Onboarding** (3 skippable screens) — what Shui is / pick interests
  (writes `users/{uid}.interests`) / how the quiz works, gating
  `RootTabView` until `hasCompletedOnboarding` (local pref from Phase 0).
- **Explore tab**, 3 levels — categories grid + "Continue learning" row +
  `.searchable` topic search (Level 1); paginated topic list with a
  Newest/Most-learners sort (Level 2); cover/progress/markdown
  description/ordered video list with a per-video state glyph
  (unwatched/watched/quiz passed/needs review), pushing Phase 2's feed at
  the exact tapped video (Level 3).
- **Profile tab** — header, progress-by-subject (category rows aggregating
  `topicProgress`, expandable to per-topic mastery bars), a liked-videos
  grid opening a feed of exactly the liked videos starting at the tapped
  one, activity stats including a due-for-review count that opens a
  review-only feed, and Settings (Account, honestly-labeled "coming soon"
  for Notifications/Privacy/Terms rather than dead toggles or fabricated
  legal-page links, and a role-gated Creator mode entry point).
- **Account screen** — sign out, delete account, linked sign-in providers.
- **Comments** — one level of threading, up to 3 visible replies per
  top-level comment with a "View N more replies" expander, a composer
  replaced by a sign-in prompt for guests (viewing stays open to
  everyone), edit within 15 minutes / soft delete any time, report, and a
  local-only block list (`UserDefaults`-backed — real server-side blocking
  is explicitly a later decision). Posting is genuinely optimistic: a
  locally-built placeholder comment appears immediately, then is either
  replaced with the server-reconciled list on success or removed with the
  draft restored on failure. New backend piece: `toggleCommentLike`
  (mirrors `toggleLike`'s video pattern), gated `requireNotGuest` per the
  spec's explicit "requires a real account, enforced by rules."
- **Deep links** — `shui://video/{id}` and `shui://topic/{id}`, the two
  shapes Phase 2's `ShareLink` already produces, presented as a full-screen
  cover from the app root rather than threaded through whichever tab
  happens to be active. `shui://` registered in `Info.plist`; an
  Associated Domains entitlement was added for Universal Links but is
  explicitly a placeholder (`example.com`) since no real domain exists yet
  — same gap already noted for the share link's missing web fallback.
- **Analytics** — the phase's full event list wired at the point each
  action actually happens (`video_started`/`video_completed` from the
  feed's own appear/completion hooks, `quiz_submitted`/`quiz_skipped`,
  `topic_started`, `interest_selected`, `sign_in_completed`,
  `comment_posted`). `ai_opened` deliberately left unwired — there's no
  real AI tutor to open yet (Phase 4), and logging it on a "coming soon"
  tap would misrepresent the metric before the feature exists.

### Real bugs caught along the way (self-review, no Xcode in this sandbox)

- `FeedViewModel` kept its own `currentUser`/`isGuest` snapshot, fetched
  once at load — signing in from inside the feed wouldn't update the right
  rail's guest-gating until the tab was revisited. Fixed by reading
  `AppEnvironment.isGuest` directly (reactive, published) instead of a
  per-screen copy — the same staleness lesson Phase 2's pull-to-refresh
  fix already taught, recurring in a new spot.
  `.navigationDestination(item:)` requires `Identifiable`, which `[Video]`
  isn't — caught before it shipped, wrapped in a small `VideoListDestination`.
- A case-sensitive-only topic-title search (the phase spec's literal
  wording) would fail almost every real typed query — added a
  denormalized `titleLowercase` field instead, kept in sync by
  `create`/`update` and backfilled in `seed_civics.ts`.
- Two new composite index requirements this phase's queries actually need
  (`topics` sorted by `learnerCount`, `comments` filtered by `parentId`
  ordered ascending for replies) — added proactively based on the exact
  query shapes written, rather than waiting to hit the same "missing
  index" wall Phase 2 hit live. One more index mistake did reach a real
  deploy though (below) — self-review and the emulator run couldn't have
  caught it, since only the real deploy validates index *definitions*
  against Firestore's actual rules for what belongs in `indexes` versus
  `fieldOverrides`.

### Verification

Unlike Phase 1/2, this phase's backend changes were verified for real in
this sandbox, not just self-reviewed: `tsc` across the whole `functions`
package (zero errors — covers `deleteAccount`, `toggleCommentLike`, and
every schema/rules change), then the real rules suite against the
Firestore emulator. That run caught one genuine regression on the first
try: the existing "owner can create their own doc" test predated the new
`isDeleted` field this phase added as a required create-time condition, so
it started failing exactly as it should have — fixed the test payload, and
added targeted coverage for both rules changes that had none yet
(`commentLikes`, `isDeleted` protection). **69/69 rules tests, 25/25 unit
tests passing.**

The Swift half has no compiler in this sandbox, same as every prior
phase — checked by hand: brace/paren balance and duplicate-top-level-type
grep across every file touched this phase, `import Firebase` confinement
re-verified, no stray `DocumentSnapshot` outside `Sources/Data/`, and every
new repository/model call site cross-referenced against its real
declaration. **Next step for the user:** `git pull`, `xcodegen generate`
(large batch of new files across `Sources/Theme`, `Sources/Views/Auth`,
`Sources/Views/Explore`, `Sources/Views/Profile`, `Sources/Views/Comments`,
`Sources/Views/Onboarding`), build in Xcode, and report back whatever the
compiler finds — plus `firebase deploy --only firestore,functions` before
any of the new backend pieces (delete account, comment likes, search) will
work against the real project.

### Deployment gotcha: a real one the emulator run couldn't have caught

The first live `firebase deploy --only firestore,functions` against
`shui-prod` failed on `firestore.indexes.json`:

```
Error: Request to .../databases/(default)/collectionGroups/comments/indexes
had HTTP Error: 400, this index is not necessary, configure using single
field index controls
```

Same underlying rule as Phase 1's gotcha #5 (a composite index that's
really just one field gets rejected as redundant), but a variant that
gotcha's fix didn't cover: it applies at `COLLECTION_GROUP` scope too, not
only `COLLECTION` scope. `deleteAccount`'s
`db.collectionGroup("comments").where("uid", "==", uid)` query needs
collection-group indexing explicitly enabled for `uid` (collection-group
queries don't get Firestore's automatic per-field indexing the way
collection-scoped queries do) — but a *single-field* enablement, even at
collection-group scope, belongs in `firestore.indexes.json`'s
`fieldOverrides` array, not the `indexes` (composite) array. The original
entry:

```json
{ "collectionGroup": "comments", "queryScope": "COLLECTION_GROUP", "fields": [{ "fieldPath": "uid", "order": "ASCENDING" }] }
```

moved to:

```json
"fieldOverrides": [
  { "collectionGroup": "comments", "fieldPath": "uid", "indexes": [{ "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }] }
]
```

Nothing short of a real deploy against real Firestore surfaces this —
`tsc` and the rules emulator (which doesn't enforce index requirements at
all) both have no way to validate an index *definition's* shape against
Firestore's actual acceptance rules. Worth remembering for any future
collection-group query that only ever filters on one field: it goes in
`fieldOverrides`, composite indexes are for genuinely multi-field queries.

### Live verification round (real device, post-build): three real bugs found and fixed

Once Phase 3 actually built and ran, the user walked through the real
"Verify" checklist by hand on-device (signed in, signed out, watched
video, submitted a quiz, browsed Explore, opened comments). That surfaced
three real bugs static review couldn't have caught:

1. **Guest feed load failed with "Missing or insufficient permissions" —
   worked signed in as admin, broke for a plain guest.** Root cause:
   `FirestoreVideoRepository.feed(categoryId:)`, `feed(categoryIds:)`, and
   `videos(inTopic:)` filtered on `topicVisibility`, `status`, and
   `isDeleted`, but never on `visibility` — even though
   `firestore.rules`' `videoIsPublic()` checks all four. Firestore denies
   an entire list query if *any* document in the matched set fails the
   rule, not just that document — so any test video with
   `topicVisibility: 'public'` (inherited from a public topic) but its own
   `visibility` field still `'private'` (never explicitly published)
   silently killed the whole feed for anyone who wasn't that video's
   owner/admin. Signed in as the admin/creator account, `isVideoOwnerOrAdmin`
   masked it; a real guest had no such escape hatch. Fixed by adding the
   missing `visibility` filter to all three queries (`VideoRepository.swift`)
   and updating the three affected composite indexes in
   `firestore.indexes.json` to match. This also blocked "Interests picked
   at onboarding change feed ordering" and topic-page browsing from ever
   being testable as a guest, since the underlying query was broken
   regardless of who called it.
2. **Quiz result screen's "Replay" button was unreachable, covered by the
   floating tab bar.** `FeedView` applied `.ignoresSafeArea()` (all edges)
   for full-bleed video, but the tab bar still docks at the bottom
   regardless — so bottom-anchored content (the quiz result card's Replay
   button, `QuizResultCard` in `QuizCardView.swift`) rendered underneath
   the tab bar's hit-testing region instead of above it. Fixed by scoping
   the ignore to `.ignoresSafeArea(edges: .top)` — the only edge actually
   worth bleeding into, since the tab bar chrome was always going to cover
   the bottom either way.
3. **`categories` (and the one seeded topic) were never populated on the
   real `shui-prod` project** — `scripts/seed_civics.ts` seeds them but is
   a manual one-time script, not something deploy runs automatically. Not
   a code bug; explained to the user and left as a manual step
   (`SEED_ADMIN_UID=<uid> npm run seed:civics`, uid from
   `bootstrap-admin.ts`). This is also why onboarding's interests step had
   nothing to pick from, forcing "Skip."

Two items from live testing turned out not to be bugs on inspection:
comment edit/delete *is* wired (`CommentsViewModel.canEdit`/`canDelete`,
surfaced via the row's "•••" menu, not inline buttons — gated to the
comment's own author within 15 minutes) — the user likely just didn't open
the menu, or was testing a comment posted under a different account after
signing out/in. Account deletion was confirmed working live.

Still open: quiz submission occasionally failed with the generic "Couldn't
submit your answers" offline-style message after a sign-out. The
`submitQuizAttempt` callable uses `requireAuth` (any signed-in user,
guests included, matching the guest-first spec — not over-restrictive),
so this isn't the same class of bug as #1 above; root cause not yet
confirmed. Needs a repro with the exact Xcode console error text, ideally
without a sign-out immediately beforehand, to rule in/out an auth-token
race versus something else.

### Live verification round 2: sign-in dead end from Account, and clearing up "why doesn't my topic show"

Retest after round 1's fixes confirmed guest feed load, comment edit/delete,
and deleted-comment anonymization all work correctly. Two more things came
up:

- **No way to sign in from a guest session except the Debug tab.** The
  Account screen told a guest "sign in to keep your progress" but had no
  button to act on it — `SignInSheet` was only ever wired to the three
  contextual triggers the spec calls out (Like, Comment composer, third
  video), never a deliberate self-service entry point. Those two aren't in
  conflict — the spec's "never a modal on launch" is about not *nagging*,
  not about removing the option — so this was a real gap, not a deliberate
  restriction. Fixed: `AccountView` now shows a "Sign in" button under that
  guest text, opening the same `SignInSheet`.
- **Debug-created topics not appearing under their category.** Two
  independent, both expected: (1) `TopicRepository.create()` always starts
  a topic `visibility: .private` by design — it only becomes visible once
  the Debug screen's "Attach test quiz + publish" step runs (`setVisibility`
  calls for both the video and the topic). (2) Separately, `Category.topicCount`
  is set once at seed time (`FieldValue.increment(0)`, i.e. always 0) and
  nothing increments it — there's no trigger anywhere in `functions/src`
  watching topic creation/publish to maintain it. That's genuinely Phase 5
  territory (creator-tooling triggers), not an oversight to fix now — the
  category tile's "N topics" label will read stale/zero regardless of how
  many real topics exist until that phase adds the maintenance trigger.
  Worth a note-to-self for Phase 5's spec review, not a Phase 3 bug.

### Definition of done: live status against the spec's §9 Verify checklist

`prompts/phase-03-discovery-social.md` §9 is the actual bar, not "it
builds." Status as of the seeded-categories retest, screenshot evidence
noted where it exists (images themselves live in chat history, not this
repo — described here instead):

| # | Item | Status |
|---|---|---|
| 1 | Fresh guest → watch → quiz, no account | ✅ confirmed live |
| 2 | Guest Like → sign-in sheet → Apple links account, progress carries over | Partial — email and Apple sign-in both now confirmed working; the specific "guest progress still present after linking" check not separately re-verified |
| 3 | Email sign-up / sign-out / sign-in / password reset | Partial — sign-in, sign-out, and password reset confirmed; new-account sign-up currently blocked by Firebase's own rate limiting from heavy test volume (`tooManyRequests`, not a bug — see round 5 below), needs a retest once that clears |
| 4 | Guest denied comment creation by rules | ✅ confirmed (emulator, `rules.test.ts:396`) |
| 5 | Interests at onboarding change feed ordering | Open — now testable since categories are seeded, not yet run |
| 6 | Topic page → Start learning → right video → Back updates progress | Open — same, now reachable, not yet run |
| 7 | Profile mastery bars match `topicProgress`, category aggregate = mean of topics | ✅ confirmed live with exact numbers: Exam Prep category showed 64% aggregate against two topics at 88% and 40% — (88+40)/2 = 64, exact match to the spec's formula |
| 8 | Comment post/reply/edit/delete/report | ✅ confirmed live (edit, delete, report, block all exercised; a deleted comment correctly renders "Deleted user" while keeping its replies) |
| 9 | `shui://video/{id}` cold start | ✅ confirmed live — tapped a `shui://video/{id}` link from Safari *inside* the Simulator (not the host Mac's browser, which doesn't know the scheme), got the "Open in Shui?" system prompt, and landed in the right video. (First diagnosed a red herring: `xcrun simctl openurl booted` appeared to do nothing — likely ambiguous device targeting from the terminal — before confirming the scheme itself works via the in-Simulator Safari route instead.) |
| 10 | Account deletion removes user, anonymizes comments | ✅ confirmed live, twice (including a full delete → recreate cycle) |

**6 of 10 confirmed** (1, 4, 7, 8, 9, 10). Not done yet — 2, 3, 5, 6 remain
open, none blocked on anything further at this point (all reachable with
the app and data as they stand now).

### Live verification round 3: Apple sign-in entitlement, and a Profile guest CTA

- **Apple sign-in failed with `ASAuthorizationError` on every attempt.**
  Root cause: `Shui.entitlements` only ever had the Associated Domains
  placeholder — the actual `com.apple.developer.applesignin` entitlement
  was never added, so `ASAuthorizationAppleIDProvider` requests fail
  regardless of device/simulator. Added the missing entitlement key. Still
  needs the "Sign In with Apple" capability enabled for the App ID in the
  Apple Developer portal (automatic if using Xcode's automatic signing —
  add the capability in Signing & Capabilities and it registers the
  portal-side change itself) before a rebuild will actually clear the
  error; Simulator can also be independently flaky for this even once
  correctly configured, so a real device is the reliable way to confirm.
- **No visible "sign up" path — confirmed by design, not a gap.** The
  email form's single "Continue" button already handles both cases via
  `continueWithEmail()` (link-first, falls back to sign-in on
  `emailAlreadyInUse`), per the phase spec's "sign-up / sign-in
  detection" — there's deliberately no separate button because there's
  only one flow.
- **Guest Profile just showed a generic "Learner" shell with nothing
  else — no invitation to sign in anywhere on the tab itself,** only
  buried in Settings → Account. Landing on your own Profile while a guest
  is exactly the "moment of need" the spec describes (not a launch nag),
  so treated as in-scope for this phase rather than deferred: added a
  `guestBanner` section to `ProfileView` — "You're browsing as a guest /
  Sign in to save your progress" with a Sign in button — shown right
  under the header whenever `environment.isGuest`.
- **`Category.topicCount` still reads 0 even with real published
  topics** — same known gap already logged above (no maintenance
  trigger exists yet), re-confirmed live, still correctly Phase 5's job.

### Live verification round 4: Apple sign-in confirmed, a real back-button question, and quiz-failure messaging

- **Apple sign-in now works** after the entitlement fix and enabling the
  capability in Xcode's Signing & Capabilities. Item #2 from the Verify
  checklist is now fully unblocked.
- **Guest quiz submission does *not* require sign-in — confirmed by
  reading `submitQuizAttempt`'s `requireAuth()` (checks only that
  `request.auth` exists; anonymous sessions have a valid `request.auth`
  too) and `QuizRepository.submit()` client-side (calls the callable
  directly, no guest gate).** This matters because the user's live
  testing produced the "Couldn't submit your answers" failure screen
  specifically as a guest and asked whether quiz submission should
  require sign-in with clearer messaging to that effect. It doesn't, and
  saying so would be wrong — verify item #1 (fresh guest → watch → quiz)
  was already independently confirmed working earlier this phase, so
  guest quiz submission is proven to succeed under normal conditions.
  The actual cause of this specific failure is still unconfirmed (most
  likely Simulator network flakiness, but not proven).
  What *is* a real, shippable improvement regardless of that unknown
  cause: the failure card previously showed a canned "we'll retry
  automatically" message for *any* failure reason, which lies whenever
  the real cause isn't actually a connectivity problem. Fixed:
  `LessonEndState.submissionFailed` now carries the real error message;
  `FeedPageViewModel.failSubmission(_:)` classifies it (`NSURLErrorDomain`
  → nil → keeps the honest "retry automatically" copy; anything else,
  including a real `HttpsError` reason, → shows that actual message
  instead). Next time this reproduces, the on-screen text itself should
  say why, instead of guessing being the only option.
- **"Start learning works but back button did not work"** — reported
  live, not yet root-caused. `TopicPageView`'s "Start learning" is a
  genuine `NavigationLink` push to `FeedView(mode: .topic(...))`, and
  `FeedPageView`'s custom back chevron (shown whenever `topicModeInfo`
  is non-nil) calls the standard `@Environment(\.dismiss)` — this is
  exactly the supported pattern and reads correctly on inspection, no
  bug found by static review. Two real possibilities: the small chevron
  button itself is broken in a way review didn't catch, or the learner
  tried an edge-swipe-back gesture instead, which the feed's own paging
  scroll/tap gestures plausibly eat before it reaches the system's
  interactive-pop recognizer. Needs a repro specifically confirming
  which gesture was used before this can be fixed with confidence.

### Live verification round 5: the back button *was* a real bug, plus one still-open

- **Back button confirmed broken via both interaction paths** — tap on
  the chevron and an edge swipe both failed, which rules out "wrong
  gesture" as the explanation and points at something more fundamental.
  Root cause: `FeedPageView` read `@Environment(\.dismiss)` itself, but
  it's instantiated inside `FeedView`'s `LazyVStack { ForEach { ... } }`
  — environment values are not always reliably re-resolved for views
  lazily created inside `LazyVStack`, a known SwiftUI rough edge, and
  this looks like exactly that: the button's `dismiss()` call was
  reading a stale/inert action. Fixed by capturing `@Environment(\.dismiss)`
  once at `FeedView`'s own top level — *outside* the `ScrollView`/
  `LazyVStack` — and threading it down as a plain `onBack: () -> Void`
  closure instead of letting each lazily-created page re-resolve the
  environment itself. (The edge-swipe failure may have a second, separate
  cause — `.toolbar(.hidden, for: .navigationBar)` is separately known to
  sometimes disable the system's interactive-pop gesture on some iOS
  versions — not touched here since the deliberate on-screen button is
  the primary affordance and is now fixed; worth another look only if
  swipe-to-go-back specifically still doesn't work after this.)
- **Email sign-up "bug" retracted — it wasn't one.** The follow-up
  attempt surfaced the real error: "We have blocked all requests from
  this device due to unusual activity" — `AuthErrorCode.tooManyRequests`,
  Firebase's own abuse-protection rate limit, not an app bug. This
  session had run a genuinely high volume of auth traffic against the
  real project in a short window (repeated sign-in/sign-out, account
  delete/recreate cycles, Apple sign-in retries) and tripped Firebase's
  own throttling. That almost certainly explains the earlier
  "malformed or expired credential" `invalidCredential` error too — an
  earlier stage of the same throttle escalating, not a distinct logic
  bug in `continueWithEmail()`/`link()`. No code fix applies here; it's
  a Firebase-side policy reacting to test volume, not something the app
  controls. Retest once the block clears (these are typically
  temporary) to confirm sign-up itself is fine. Worth remembering as a
  general lesson for the rest of this project: heavy back-to-back
  manual auth testing against a real (non-emulator) Firebase project
  can trip this on its own, independent of any real bug — don't assume
  a bug from an auth error without checking whether it's actually a
  rate limit first.

## Phase 4 — The AI tutor

### Goal

`prompts/phase-04-ai-tutor.md`: a grounded chat behind the feed's `sparkles` button, two
modes (Discuss, Quiz me) on one persistent thread per video, server-side context assembly
(never client-side), streamed responses, rate limiting, and a conversational miss pulling
that video's review date forward through the same SM-2 scheduler quiz answers use.

### What got built

**Backend** (`functions/src/ai/`):
- `grounding.ts` — assembles video/topic/quiz/learner-record/recent-thread context
  straight from Firestore server-side. Topic neighbors (previous/next video title) come
  from a live query over the topic's own video list, not a denormalized field. Transcript
  truncates at a flat ~12k-character budget rather than the spec's ideal
  relevance-ranked excerpt — nothing in this app has a real transcript yet to rank
  against, so a flat truncation is the honest, testable version of that requirement
  today, not a shortcut taken silently.
- `prompts.ts` — versioned (`PROMPT_VERSION`) Discuss/QuizMe templates sharing one
  grounding preamble. Solves a real design problem: streamed free text can't also carry
  structured hints (suggested-reply chips, a retention verdict) without a second model
  call, so the model is instructed to append a delimited `<<<META>>>...<<<END_META>>>`
  JSON block after its reply, which the callable strips from what's shown/persisted and
  parses separately (`parseModelOutput`/`extractVisibleText`, covered by
  `prompts.test.ts`). Malformed or missing meta degrades to no chips / no retention
  update rather than failing the turn — the prose is still good even if the trailing
  block isn't.
- `modelClient.ts` — `ModelClient` protocol with `AnthropicModelClient` (real, streaming
  via the async-iterator form so batched Firestore writes stay ordered) and
  `FakeModelClient` (scripted, chunked delivery for evals/tests). Model and API key are
  Function config/secrets (`AI_MODEL`/`AI_API_KEY`), never in code, per the spec.
- `rateLimit.ts` — 30/hour + 300/day, one `users/{uid}/aiUsage/{yyyy-mm-dd}` doc with a
  24-slot hour-count array covering both caps in a single transactional write.
- `aiTutorMessage` callable — auth via `requireNotGuest`; verifies the caller can
  actually read the video (mirrors `videoIsPublic || owner/admin` since Admin SDK
  bypasses rules and this check has to happen in code); rate-limits; assembles
  grounding; streams the model response, throttling Firestore writes to the assistant
  message doc every 200ms rather than on every token; applies
  `retentionAssessment.verdict` (`missed`→`again`, `shaky`→`hard`) through the exact
  same `schedule()`/`ReviewState` SM-2 code path `submitQuizAttempt` already uses, not a
  second scheduler; finalizes the message and returns.
- **Streaming architecture — a real, documented call, not an accident.** The spec
  explicitly allows either "an HTTPS Function with SSE (or Firestore-document streaming
  if that proves simpler on iOS)". Went with Firestore-document streaming:
  `aiTutorMessage` writes an assistant message doc immediately (`status: "streaming"`),
  updates its `text` field as tokens arrive, and finalizes it
  (`status: "complete"`) when done — the client just listens to the message doc like any
  other Firestore read. Chosen because (a) it was never confirmed the Firebase
  Functions **iOS** SDK actually supports the newer streaming-callable protocol — that
  feature is documented primarily for the Web SDK — and guessing wrong would mean
  building the whole feature against an API that doesn't work on the platform that
  matters, and (b) every other repository in this app already reads Firestore directly;
  a listener is the one new pattern, not two.
- **`submitQuizAttempt` gained `lastMissedQuestionIds`** on `videoProgress` — grounding
  requirement #4 ("probing exactly what they missed") needs to know *which* questions
  were wrong, and nothing previously stored that, only the aggregate score. Small,
  backward-compatible addition to an existing transaction, from the last attempt only
  (not accumulated across attempts).
- **Evals** (`functions/src/ai/evals/`): 5 hand-written `GroundingContext` fixtures (two
  mirroring the real seeded civics topic — one clean pass, one with a specific missed
  question; a no-transcript video for the degradation path; a no-quiz video with
  existing thread history; a transcript well over the truncation budget) and 21 cases
  across the spec's six categories (in-scope, out-of-scope, partial-credit,
  confidently-wrong, "I don't know", hostile). `npm run eval` checks deterministically:
  word-count limits (80 discuss / 60 quizMe), the meta block parses, one `?` per
  `quizMe` turn, retention set when expected. The spec's model-graded rubric checks
  (stays in scope, acknowledges the correct part first, never contradicts the
  transcript) are explicitly **not** implemented — that needs real judgment, either a
  second model call or human review, and is scoped-out real work, not an oversight.
  **Nothing in this sandbox has model API credentials**, so this has only been smoke-
  tested (`npm run eval` with no key runs the full harness end-to-end and reports every
  case `SKIPPED` — proves the harness works, proves nothing about the prompts). Real
  scores need `AI_API_KEY` set and a real run.

**iOS** (`Shui/Sources/`):
- `AIMessage.swift`, expanded `AITutorRepository` — `FirestoreAITutorRepository`
  (`observeThread` bridges a Firestore snapshot listener into
  `AsyncThrowingStream<[AIMessage], Error>` — the first live-listener usage anywhere in
  this codebase, everything before this read Firestore one-shot) and
  `InMemoryAITutorRepository` (scripted fake for previews, matching the spec's ask).
  `AITutorError` maps `FunctionsErrorCode` cases to specific inline messages
  (rate-limited, not-signed-in, network) rather than a generic failure string.
- `AITutorViewModel` — owns the listener `Task` and mode switching. Switching to a mode
  with no messages yet in the thread auto-triggers that mode's own session-start turn
  (`@Published var mode { didSet { ... } }`), matching "switching mid-thread inserts a
  divider rather than clearing history." The very first session-start is gated on the
  listener's *first real snapshot*, not a fixed delay, to avoid racing a redundant
  opener against a thread that's still loading.
- `AITutorSheet` — Discuss/Quiz me segmented control, chat bubbles (assistant left/
  learner right, reusing theme tokens the same way Comments does), a three-dot indicator
  before the first token and a blinking cursor during streaming, suggested-reply chips,
  mode-change dividers in the transcript, and specific inline states for rate-limit/
  network errors (the "empty transcript" state needs no special UI — it's just the
  tutor's own honest opening message, per the prompt).
- **Guest gating moved to the rail button itself**, not inside the sheet — Comments
  intentionally stays open to guests (only its composer is gated, a Phase 3 decision);
  AI Tutor is different because the spec wants guests routed to sign-in *before* the
  tutor ever opens, so `FeedRightRail`'s AI button now checks `isGuest` the same way its
  Like button already did, unlike its Comments button.
- **Video pauses behind the sheet and resumes exactly where it was** — tracked via a
  local `wasPlayingBeforeAITutor` flag in `FeedPageView`, so a video that was already
  paused before opening AI doesn't get force-resumed on dismiss.
- Removed `ComingSoonSheet` — its only two call sites (Comments, AI) are both real
  screens now, so it was fully dead code, not kept "just in case."

### Verification

Real this time, not just self-review: `tsc` across the whole `functions` package (zero
errors), `npm run test:functions` (33/33 — five new `prompts.test.ts` cases for the
meta-block parser, the trickiest pure logic in the phase), the existing 69-case rules
suite against a real Firestore emulator (no rules changes needed — Phase 3 already
scoped `aiThreads`/`aiUsage` correctly), and the eval harness smoke-tested end-to-end
(no live model, so every case reports `SKIPPED` rather than a real score).

The Swift side has no compiler in this sandbox, same as every prior phase — checked by
hand: brace/paren balance across every new/changed file, cross-referenced every
`FunctionsErrorCode`/`FunctionsErrorDomain`/`FunctionsErrorDetailsKey` usage against
documented Firebase iOS SDK symbols (not verified by an actual compile — flagged
explicitly since this is a newer, less-traveled corner of the SDK than anything prior
phases touched), and confirmed `AIMessage`'s optional properties all have explicit `= nil`
defaults so the memberwise-init call sites in `InMemoryAITutorRepository` actually
compile. **Next step for the user:** `git pull`, `xcodegen generate` (new
`Sources/Views/AITutor/` folder), build in Xcode and report whatever the compiler finds —
plus set `AI_API_KEY` via `npm run secrets:push` (renamed from `set-r2-secrets.sh` to
`set-secrets.sh` this phase, now that it pushes more than R2 credentials) and
`firebase deploy --only functions` before any of this works against the real project.

### Regression found live: the earlier back-button fix broke paging

First real live-testing bug against the actual deployed Phase 4 build: pausing a video
showed the *next* reel already visible (and playing) in a sliver at the bottom of the
screen, behind the tab bar — one screen showing the tail of the current page and the head
of the next one at once.

Root cause: this phase's earlier back-button fix (`FeedView.swift`, this same
PROGRESS.md's round-5 entry) changed `.ignoresSafeArea()` from all edges to `.top` only,
specifically to keep the quiz card's buttons clear of the floating tab bar. That
side-stepped the button-clearance problem but created a worse one — `.ignoresSafeArea()`
doesn't just change *reporting*, it changes what size the view is actually proposed by its
parent. Scoping it to `.top` meant each page's own frame (`.frame(width:height:)`, sized
from the same `GeometryReader`) shrank by the bottom safe-area inset, i.e. below one true
screen height. The vertical paging `ScrollView` still pages by exactly one page-frame per
swipe, so a page shorter than the physical screen left a gap at the bottom where the
*next* page's top edge showed through — worse than the original bug, and only obviously
visible while paused (a playing video draws the eye away from the seam).

Fixed by separating the two concerns that got conflated: pages need full screen height for
paging to line up with the physical screen, and the quiz card's buttons need to clear the
tab bar — these are different problems needing different fixes, not one shared frame
adjustment. `FeedView` now nests two `GeometryReader`s: an untouched outer one that still
sees the real, tab-bar-inclusive safe area (`.ignoresSafeArea()` zeroes that reporting for
everything *inside* it, so reading it has to happen *above* that modifier), and an inner
one with the full (all-edges) `.ignoresSafeArea()` restored for correct full-height
paging. The outer reader's `safeAreaInsets.bottom` is threaded explicitly through
`FeedPageView` into `QuizOverlayContainer` as `tabBarBottomInset`, applied as bottom
padding on the card's actual content (not its decorative background, which still extends
flush to the true bottom edge) — the same explicit-parameter-threading pattern as `onBack`
from the earlier round, not a custom `@Environment` key, for the same reason: no
dependency on environment values propagating reliably through the `LazyVStack`/`ForEach`
these views live inside.

### Real deploy error: missing composite index for grounding's sibling-video query

`aiTutorMessage` failed every time with a bare "INTERNAL" (Firebase scrubs `internal`-code
error messages before they reach the client) — real cause, from the actual Cloud
Functions logs: `FAILED_PRECONDITION: The query requires an index`. `grounding.ts`'s
"previous/next video in this topic" query (`topicId ==`, `status ==`, `isDeleted ==`,
`orderBy(order)`) needs a composite index this phase never declared in
`firestore.indexes.json` — a real oversight, not caught by `tsc` or the unit tests since
neither actually executes a live Firestore query, and the emulator run doesn't enforce
index requirements at all (same category of gap Phase 1's and Phase 3's index gotchas
were). Existing `videos` indexes are all close but not exact matches — they include
`visibility`/`topicVisibility` as additional equality filters this specific query doesn't
use, and Firestore composite indexes require an exact field-set match, not just a prefix.
Added the missing index. Firestore index builds take a few minutes even after being
declared — the fastest fix for anyone hitting this before a redeploy lands is the direct
"create it here" link Firestore includes in its own error message, which builds the exact
same index without waiting on a functions deploy at all.

While investigating, also traced (from the client's, not yet confirmed against real
Firestore data) a **separate, pre-existing "INTERNAL" on `submitQuizAttempt`**: its
`"Quiz answer key missing for question X"` guard throws `HttpsError("internal", ...)`
when a video's `quiz/current` and `quiz/answers` docs have mismatched question IDs.
`saveQuiz`'s transaction writes both atomically from the same input array
(`splitQuizForStorage`), so this shouldn't happen from normal use — likely stale/
inconsistent debug data on the specific video tested rather than a code bug. Not fixed in
code since there's nothing to fix without evidence of an actual write-path bug; the
concrete next step is checking that video's `quiz/current`/`quiz/answers` docs directly in
the Firestore console, and re-running "Attach test quiz + publish" for it if they're out
of sync.

### Live verification: rate-limit reset time silently failing to parse

Confirmed live: hitting the rate limit correctly showed the cap message, but always as
the generic "try again later" — never the specific reset time, even though the server
sends one (`resetAt` in the `HttpsError`'s `details`). Root cause: `usage.resetAt
.toISOString()` server-side (JavaScript) always includes milliseconds
(`"2026-08-05T01:00:00.000Z"`), but `ISO8601DateFormatter()`'s *default* configuration
doesn't parse the fractional-seconds component and silently returns `nil` — a real,
easy-to-miss cross-language date-format mismatch, not something `tsc`, unit tests, or the
rules emulator could ever have caught (nothing in this sandbox parses a real ISO date
string against a real Swift date formatter). Fixed by trying
`.withFractionalSeconds` first, falling back to the plain format.

While fixing it, also turned this into a real live countdown rather than a static
timestamp — the user asked directly for "a timer... so they could know when it would get
reset." `AITutorViewModel` now exposes the raw `rateLimitResetAt: Date?` separately from
the generic `errorMessage`, and `AITutorSheet` renders it via SwiftUI's built-in
`Text(_:style: .timer)`, which re-renders on its own as time passes — no manual `Timer`
or polling needed. The composer and suggested-reply chips also disable themselves while
rate-limited, rather than letting a tap round-trip to the server just to fail the same
way again.

### Eval harness bug: every case erroring with `model: String should have at least 1 character`

Ran `npm run eval` for real for the first time (with `AI_API_KEY` actually set) — all 22
cases failed immediately with a 400 from Anthropic's API, not a scoring failure. Root
cause: `AnthropicModelClient` read the model name via `aiModel.value()`, a Firebase
`defineString("AI_MODEL", { default: "claude-sonnet-5" })` parameter. That resolution
path — including the declared default — only works correctly inside the real,
Firebase-managed Functions runtime (a live deploy or the emulator); a bare `node
lib/ai/evals/run.js` process, which is what `npm run eval` actually runs, never goes
through that machinery, so `.value()` silently returned an empty string instead of
falling back to `"claude-sonnet-5"`, and the API rejected the empty model name. This is
the mirror image of a gotcha already documented for `defineSecret`: secrets *are* always
delivered as plain `process.env` vars by Secret Manager regardless of context (which is
why `AI_API_KEY` worked fine here) — `defineString`'s default-fallback is not the same
kind of passthrough, it's part of Firebase's own runtime, not something `.value()`
reapplies generically outside it.

Fixed two ways: `AnthropicModelClient`'s constructor now takes an optional explicit
`model?: string`, falling back to `aiModel.value()` only when the caller doesn't supply
one (the real `aiTutorMessage` callable's call site is unchanged and unaffected — it runs
inside the real runtime where `.value()` was never broken); and the eval runner now
passes one explicitly (`process.env.AI_MODEL || "claude-sonnet-5"`), since it's exactly
the kind of bare-`node` caller the bug was about. Re-verified after the fix: `tsc` clean,
`npm run test:functions` (33/33) and `npm run test:rules` (69/69) both still pass. Real
scores from an actual `npm run eval` run against the live API are still needed from the
user — this only fixes the harness itself, not the prompts' quality.

### Explicit scope decision: transcript-dependent testing backlogged until real videos exist

User instruction, verbatim: *"anything related to transcript lets backlog it and test it
again once we have video."* Logged here as a deliberate, user-directed scope cut, not an
oversight — every video in the app today is a placeholder with no real transcript, so
transcript-dependent behavior can only exercise the spec's own honest-degradation path
(tutor admits it only has the lesson summary; "Quiz me" falls back to multiple-choice),
never the grounded, transcript-aware behavior the spec actually describes. Retesting
those items against placeholder data would just re-confirm the fallback path, not the
real feature.

### Definition of done: live status against the spec's §7 Verify checklist

`prompts/phase-04-ai-tutor.md` §7, the actual bar:

| # | Item | Status |
|---|---|---|
| 1 | Open AI on a video with a transcript: three starter questions, grounded in-scope answer | Backlogged — no video has a real transcript yet; only the honest-degradation path is exercisable today, per the user's explicit instruction above |
| 2 | Ask something the video never covers: tutor says so instead of inventing an answer | ✅ confirmed live |
| 3 | "Quiz me" asks one question at a time, accepts a correctly-worded-differently answer | ✅ confirmed live |
| 4 | A conversationally missed concept moves that video's `dueDate` earlier | Backlogged by user request — retest once real videos/transcripts exist |
| 5 | Reopening the same video restores the thread | ✅ confirmed live — relaunched the app and both comments and the AI thread were still there |
| 6 | Exceeding the rate limit shows the cap message with a reset time | ✅ confirmed live (screenshot), plus the live-countdown-timer feature added in response |
| 7 | A video with no transcript still opens the tutor with the honest degraded opener | Backlogged — folded into item 1's transcript backlog, since this is the fallback path item 1 will exercise until real transcripts land |
| 8 | Guest tapping AI gets the sign-in sheet | ✅ confirmed live — tapping AI while signed out prompts sign-in, same as Like |
| 9 | `git grep` finds no model API key anywhere in the iOS target | ✅ confirmed — `git grep -niE "sk-ant-\|anthropic.*api.*key\|AI_API_KEY" -- 'Shui/*'` returns nothing |
| 10 | `npm run eval` passes the assertion thresholds; scores table committed | Closed with a known, accepted limitation — two real runs committed to the eval README; a real metadata-compliance gap found (see below) does not fully clear on retest, and the user explicitly chose to accept it rather than pursue the structural fix right now |

**6 of 10 confirmed clean** (2, 3, 5, 6, 8, 9), plus one already-verified prerequisite
(build/deploy/tsc/tests, covered under Verification above but not itself a numbered item
here). 3 items formally backlogged by explicit user instruction (1, 4, 7) pending real
video transcripts. Item 10 is closed by explicit user decision rather than a clean pass —
see below for why.

### First real eval run: a harness bug and a genuine prompt-compliance gap

User ran `npm run eval` for real (`AI_MODEL=claude-sonnet-5`) after the model-resolution
fix above and pasted the full 21-row table — no `SKIPPED`, no `ERROR`, and the script
itself reported success. Reading the table caught two things the exit code didn't:

- **`run.ts`'s pass/fail gate had its own bug**: it checked word-limit, format-block, and
  one-question-mark, but never checked the "retention set" column — so 3 real failures
  visible right there in the table (`cbg-partial`, `cbg-dontknow`, `cbr-dontknow`, all
  missing a `retentionAssessment` the prompt says they should have set) still produced
  "0 case(s) failed" and exit code 0. Fixed by including that column in the failure
  filter — the harness's headline pass/fail now actually matches what its own table says.
- **A real prompt-compliance gap, not just a test artifact**: those 3 misses cluster on
  exactly the turns where a learner didn't give a clean right/wrong answer — a partial
  answer, or "I don't know." That matters beyond the eval: item 4 above (a missed concept
  pulls the review date forward) depends on the model actually tagging those turns, and
  "I don't know" is the single clearest signal of a miss a learner can give. `prompts.ts`'s
  output-format instructions technically covered this ("the turn you evaluated the
  learner's answer") but didn't spell out that a non-answer or a hedge still counts as
  evaluating that turn. Strengthened the instruction to say so explicitly, bumped
  `PROMPT_VERSION` to `v2`. Re-verified: `tsc` clean, `test:functions` 33/33,
  `test:rules` 69/69. Needs one more real `npm run eval` run to confirm `v2` actually
  closes the gap — flagged in the eval README rather than assumed fixed.

### Second real eval run: the gate fix works, the prompt fix only partly did — accepted as a known limitation

User re-ran `npm run eval` against `v2`. The fixed pass/fail gate worked as intended this
time — it correctly reported "5 case(s) failed a deterministic assertion" instead of a
false "0 failed." Reading those 5:

- **2 word-limit overruns** (`nt-out-of-scope` 91w, `nt-partial` 72w vs. their mode's
  limit) — both passed comfortably in the first run on the same case/fixture (73w, 48w).
  Read as ordinary sampling variance (no fixed temperature/seed on these calls), not a
  regression from anything changed between runs.
- **3 metadata-compliance failures** (`cbg-partial`, `cbg-dontknow`, `cbr-dontknow`) — the
  `v2` wording fix narrowed but did not close the gap: `cbg-dontknow` still shipped with
  `retentionAssessment: null` despite the meta block otherwise being present, and two cases
  (`cbg-partial`, `cbr-dontknow`) omitted the meta block *entirely* this run — a failure
  mode the first run hadn't even shown. Ruled out `maxTokens: 500` truncation as the cause
  (same budget the real callable uses; these are 20-90 word responses, nowhere near it) —
  this is the model genuinely not emitting the block on some turns, not a code bug on our
  side.

**The honest conclusion**: no amount of prose in the system prompt is going to reach 100%
compliance here — the real fix is structural (forcing the metadata through Anthropic's
tool-use/schema-constrained mechanism instead of a free-text delimiter the model has to
remember to append), which is real architecture work across the streaming path, not a
prompt tweak. Asked the user how to handle it before calling Phase 4 done: pursue that
structural fix now, or accept the current behavior — which already degrades gracefully,
same "degrade honestly" pattern used elsewhere in this phase (no crash, just an
occasionally-skipped suggested-reply row or SM-2 update) — as a known, logged,
non-blocking limitation. **User chose to accept it as a known limitation for now.** Logged
in the eval README's new "Known limitation" section; not pursuing the tool-use rework
unless it proves common enough in real usage to matter.

### Definition of done, final: item 10 closed as "accepted with a known limitation," not a hidden pass

Correcting the table above: item 10 (`npm run eval` passes the assertion thresholds) does
**not** actually pass clean — the harness's own (now-correct) gate reports real failures.
Marking it done anyway would misrepresent what the two real runs above found. Status:
**closed by explicit user decision** to accept the known metadata-compliance limitation
rather than pass all thresholds, with both real runs and the reasoning committed to the
eval README for anyone who revisits this later. Practically: **7 of 10 items now resolved
one way or another** (2, 3, 5, 6, 8, 9 confirmed clean; 10 closed-with-known-limitation),
3 backlogged by explicit user instruction pending real video transcripts (1, 4, 7). Nothing
left open and untriaged.

## Phase 5 — Creator mode

### Goal

`prompts/phase-05-creator-mode.md`: make the app self-sufficient. Adding a topic,
uploading a video, writing its quiz, and publishing all happen inside the app on a phone —
no code change, no script, no redeploy. Content stops being a build artifact.

### Phase 1 had already built more of this than expected

Before writing anything, checked what existed. The upload presign pair
(`createVideoUpload`/`finalizeVideoUpload`/`createThumbnailUpload`), both publish gates
(`setTopicVisibility` refusing a topic with no ready video, `setVideoVisibility` refusing
a video with no quiz), `saveQuiz`, `assignRole`, and `softDelete*` were all already
there — and the Firestore rules already allowed a creator to create private topics and
edit plain fields while fencing off `visibility`, the counters, and `createdBy`. Phase 1
anticipated this phase properly, so 5.1 was filling gaps rather than building a layer.

### What got built

**Backend** (new callables): `reorderTopicVideos` and `updateVideoMetadata` (every client
write to `videos` is denied by rule, so even a drag reorder needs a Function),
`createTopicCoverUpload`, `actionReport` and `saveCategory` for the admin surface, and
`suggestQuizQuestions` for AI quiz drafting.

Two design calls worth recording:

- **`reorderTopicVideos` takes the whole intended order, not a `(from, to)` pair.** A drag
  rewrites every affected row's `order` anyway, and sending the full result makes the
  write idempotent and immune to the client and server disagreeing about the starting
  order. It rejects a list that doesn't exactly cover the topic's live videos rather than
  applying a partial reorder — a silently dropped row would corrupt feed ordering.
- **`suggestQuizQuestions` demands pure JSON, and sidesteps Phase 4's reliability gap by
  construction.** The tutor has to append structured metadata *alongside* prose in a
  delimited block, which two real eval runs showed the model sometimes omits entirely. A
  quiz draft has no prose half — the entire response is the JSON — so the schema can be
  demanded directly with no marker to miss. It also **refuses outright when a video has no
  transcript**: a plausible-looking quiz drafted from a title alone is the easiest way to
  ship a wrong one, and a creator can't tell by looking.

**Five composite indexes declared up front**, derived from the new creator/admin queries
rather than discovered on deploy. Missing indexes bit this project in Phases 1, 3, *and* 4
for the same structural reason every time: `tsc`, unit tests, and the rules emulator all
pass without them, and Firestore requires an exact equality-field-set match, so the
existing `topics`/`videos` indexes don't cover a narrower query. This is the first phase
where that lesson was applied before a deploy instead of after one.

**iOS**: role now comes from the ID token's custom claim rather than the
`users/{uid}.role` display mirror, and is force-refreshed on every foreground —
without that re-mint, a newly granted creator role stays invisible for up to an hour,
because claims are baked into the token when it's minted. That refresh is what makes §1's
"appears without a reinstall" actually true.

Then the authoring surface itself: creator dashboard, topic editor (drag reorder, inline
publish checklist, markdown preview, tag chips, typed-title delete confirmation), the
upload flow, the quiz builder, the admin surface, and local draft persistence. Details are
in the commit messages; the decisions worth keeping:

- **The quiz preview renders through the genuine feed `QuizAnsweringCard`**, not a
  lookalike. The spec asks for the real card because "authoring blind is how bad quizzes
  ship," and a re-creation would drift from the real one over time. That needed a small
  refactor — the card now takes an `onAdvance` closure instead of the whole
  `FeedViewModel` — plus a preview-only entry point on `FeedPageViewModel`, because the
  normal path gates on `video.hasQuiz`, which is false for exactly the case preview exists
  to serve: a quiz being written for the first time. Preview loops back to the first
  question rather than submitting, since grading a draft would write an attempt against a
  quiz the server has never seen.
- **Local drafts are offered on reopen, never auto-applied.** Silently preferring the
  local copy would be its own kind of data loss when the same topic was edited from
  another device. Cleared only once a server write actually succeeds.
- **Server error messages are surfaced verbatim** wherever a publish gate or validation
  can reject — "Add a quiz before publishing this video" is more useful than anything
  generic, and the inline checklist means the rejection is rarely the first the creator
  hears of it.

### Real bugs caught in self-review

No Swift compiler in this sandbox, same as every prior phase, so verification was bracket
balance plus cross-referencing every symbol against its definition. That found:

- **`saveCategory` wrote the wrong field names** — `symbolName` where the `Category` Swift
  model and the seed script both use `sfSymbol` plus `accentHex`, and it never wrote the
  `slug` field the model decodes as non-optional. Every category created from the admin
  surface would have failed to decode client-side.
- **`AVAssetExportSession.export()` is iOS 18+**; this project targets 17. Switched to the
  `exportAsynchronously` continuation form.
- **`FlowLayout` didn't exist** — written against the `Layout` protocol rather than a
  `GeometryReader`, so the tag field reports the right height on first pass instead of
  reflowing visibly.
- **`CreatorTopicSummary.id` used `UUID()` as a fallback**, which mints a new value on
  every access and would have broken `ForEach` identity on every render.
- **`.onMove` without an `EditButton`** is an affordance that exists but can't be reached.
- A **redundant `Identifiable` conformance** on `Topic` (it already conformed) — a hard
  compile error, not a warning.
- Also worth recording: the bracket checker itself had a bug, reporting a false imbalance
  because it stripped `//` inside a URL literal as a comment. Fixing the checker's
  ordering cleared it. A tool that reports phantom problems is worse than no tool, so it's
  saved with that ordering documented.

### Verification

Backend is real: `tsc` clean, 44 unit tests (11 new for the AI draft parser — fence
stripping, dropping questions that would fail `saveQuiz` anyway, refusing junk), and 77
rules tests (8 new for the paths the topic editor writes directly — public-on-create
denied, counters and `createdBy` not hand-editable, admins can reach other creators'
topics, other creators can't).

**The Swift side has not been built on a real Mac.** Every prior phase surfaced real
compiler errors this sandbox couldn't catch, and there's no reason this one is different —
it's also the largest Swift surface of any phase so far. **Next step for the user:** `git
pull`, `xcodegen generate` (new `Views/Creator/` and `Views/Components/` folders — no
`project.yml` change needed, it globs `Shui/Sources` recursively), build, and report what
the compiler finds. Then `firebase deploy --only functions,firestore:indexes` before any
of it works against the real project.

§9's verify checklist is end-to-end on a physical device with a creator account and hasn't
been started — that's the next real milestone, not something to claim in advance.

### Live verification: real bugs found and fixed against the actual build

First live testing round against a real device surfaced a real problem list, each fixed
and pushed separately (full reasoning lives in the individual commit messages; summarized
here): a cover-image cache-busting bug (replacing a topic's cover wrote to the same
deterministic R2 key, so `AsyncImage` never re-fetched it), no way to upload from
Files/iCloud Drive (Photos-only picker), a haptic on publish, the `categories.topicCount`
counter reading 0 (see below), cover images never actually rendered anywhere in the
learner-facing Explore UI despite being uploadable, a two-level-visibility trap (a
published topic with no individually-public video inside it renders as empty to a
learner, with nothing telling the creator why), a dead "Explore more topics" button in an
empty topic-scoped feed, a topic hero redesigned to overlay its title on the cover image
with a proper scrim instead of plain text sitting awkwardly below it, the quiz reveal
rebuilt from a step-through-one-question flow into a single scrollable summary, the tab
bar hiding during video playback and reappearing on pause (plus a real reactivity bug
where it froze hidden the first time this shipped — `FeedPlayerPool`'s own `@Published`
changes weren't propagating through `FeedViewModel`'s `objectWillChange`, fixed by
forwarding it explicitly), and a pre-existing "About this lesson" full-screen sheet
replaced with the inline read-more/show-less pattern used everywhere else once its
existence turned out to be a Phase 2 leftover nobody had actually asked for as a sheet.

**The `topicCount` saga, resolved by removing the failure mode rather than chasing it
further:** deployed a Cloud Functions trigger (`onTopicWritten`) to maintain
`categories/{id}.topicCount`, confirmed correct on paper, and it still read 0 after two
separate rounds of live testing. Rather than keep guessing at a bug I have no way to
confirm without direct access to the user's Cloud Functions logs or live Firestore data,
replaced the *learner-facing* count entirely with a live Firestore aggregate query
(`Query.count.getAggregation(source: .server)`) run per category on every Explore load —
always correct, no trigger to deploy, no one-time write needed to pick up an
already-published topic, and (a genuine bonus) needs no composite index at all, since
three equality-only filters don't require one. The trigger and the stored field stay in
place for the lower-stakes admin category list, which nobody has reported as broken.

### Explore search: word-for-word keyword matching, and a scope decision on ranking

**The bug**: search only matched topics whose *title* literally started with the typed
text (`searchByTitlePrefix`, a `titleLowercase` range query) — "How to" matched a topic
titled "How to life live to the fullest," but "fullest," "life live," or any of the
video's own tags (healing, life, enjoy, personal, development) did not, because Firestore
has no native full-text search and nothing tokenized text into independently-matchable
words.

**The fix**: `SearchKeywords` (`Shui/Sources/Data/SearchKeywords.swift`) — one tokenizer
shared by both the write side and the read side, which is what actually matters here: if
the stored index and a typed query were tokenized differently, matches would silently
miss cases nothing would catch until someone typed the "wrong" word. `TopicRepository.
create`/`update` now write a `searchKeywords: [String]` array (every distinct word, 2+
characters, across title/subtitle/description/tags, capped at 60), and a new
`searchByKeywords` query matches on it via `arrayContainsAny` (up to 30 query tokens).
`ExploreView.search()` now merges three sources — local cache, the title-prefix query,
and the new keyword query — with title-prefix matches always ranked first (the clearest
possible match a query can make) and everything else ranked by how many typed words it
actually contains. Also fixed a real, pre-existing bug found while in this code: search-
as-you-type fired one Firestore query per keystroke with no cancellation, wasting reads
and letting a stale broad-query result occasionally overwrite a newer, more specific one
— added a 300ms debounce with task cancellation.

Added the composite index this needs (`topics`: `visibility`, `isDeleted`,
`searchKeywords` with `arrayConfig: CONTAINS`) — declared up front this time, not
discovered on a deploy failure. This is a client-only change plus one index; no Cloud
Function involved, no per-search API/token cost. **A topic saved before this ships has no
`searchKeywords` field yet** and won't be keyword-matchable until it's next edited and
saved — same "needs one more touch" caveat as the topicCount trigger had, worth knowing
about rather than rediscovering as a fresh "why doesn't search find this" report.

**Backlog, explicitly scoped out at the user's request: paid topic ranking ("boosting").**
The user's stated future direction — a creator can pay to have their topic show up first
in search — is a genuinely different problem from *matching*, and was deliberately not
designed around today. Firestore queries can't score or rank by relevance at all; today's
"more matching words wins" order is an honest heuristic, not real ranking. Blending a paid
boost fairly against relevance and recency by hand, on top of Firestore's query engine,
gets hacky fast — that's precisely the job a real search service (Algolia, Typesense,
Meilisearch) is built to do declaratively via first-class "promoted/boosted result"
support. Recommendation for whenever this becomes a committed feature rather than a
someday-idea: adopt one of those at that point, syncing from Firestore via a Cloud
Function trigger, rather than retrofitting ranking onto `arrayContainsAny` queries. Today's
`SearchKeywords` index is a reasonable data source to migrate off of when that happens,
not throwaway work.

### Two more live bugs, found signed out on a second account

Cross-account testing (signed out, then a fresh account) confirmed publishing genuinely
works end to end — a stranger could see and play the published topic — but surfaced two
more real bugs:

**Back button in the topic feed had a dead hit target.** The visible chevron did nothing;
tapping slightly down-and-left of it worked, with no visible target there at all. The
back `Button` sat deep inside a `ZStack` with a competing ancestor `.onTapGesture`, and
without an explicit `.contentShape()` a button's actual tappable region can drift from
where it's drawn. Fixed with `.contentShape(Rectangle())` on the button's label and
`.buttonStyle(.plain)` on the button itself (`FeedPageView.swift`).

**Tab bar stayed visible through the first autoplay**, only correctly hiding after a
later pause/unpause toggle — a different bug from the earlier "stuck hidden forever" one
(already fixed, see above). Two contributing causes: the visibility check only counted
the async-confirmed `.playing` state, missing the `.loading` state set synchronously well
before it; and an explicit `.animation()` modifier likely had its first transition
swallowed by the concurrent `NavigationLink` push transition into the feed. Fixed by
widening the state check to include `.loading` and removing the explicit `.animation()`
in favor of `.toolbar`'s own built-in transition (`FeedView.swift`).

### Save videos + a redesigned Profile "Your videos" shelf

Two enhancement requests: a bookmark-style save button on the feed (separate from Like,
private rather than a public engagement signal), and a UX pass on how saved/liked videos
surface on Profile.

**Backend** (`toggleSave` callable, `users/{uid}/savedVideos/{videoId}`) mirrors
`toggleLike`/`users/{uid}/likes` exactly in shape and rules — same owner-read,
Function-only-write, same transaction pattern — with one deliberate difference: no
video-level counter. A save is a private bookmark; nothing else in the app needs to know
how many people saved a video, only the saver does, so there's nothing to keep in sync
the way `likeCount` has to be.

**Feed UI**: a bookmark/bookmark.fill button in the right rail, directly below the AI
tutor button, matching the Like button's optimistic-toggle-then-revert-on-failure
pattern and light-impact haptic.

**Profile UI redesign**: rather than stack a growing "Liked videos" grid and a new
"Saved videos" grid one after another — competing for scroll space and duplicating the
same grid twice — both now live under one "Your videos" section with a segmented control
(Saved | Liked), the same shelf pattern short-video apps use for a profile's multiple
video collections. Defaults to the Saved tab; if a user has no saved videos yet but does
have liked ones, it opens on Liked instead so the section never opens empty when there's
something to show. Both grids were also upgraded from a generic placeholder rectangle to
each video's real thumbnail (`TopicCoverThumbnail`, already built for Explore) — a small
scope increase to the *existing* Liked grid made in the course of this work, since
shipping the new Saved grid with real thumbnails next to a Liked grid still showing
placeholders would have been an inconsistent regression in the same screen.

### Two more real bugs: the Creator entry point disappearing, and the tab bar's actual root cause

**Creator button missing after switching from a normal account to an admin account,
in-session.** `environment.role` (the ID token's custom claim, gating whether the
Creator entry point in Settings is reachable at all) is deliberately cached rather than
re-fetched on every read — the existing design re-mints it on app foreground so a
newly-granted role shows up without a reinstall. But `SignInSheet`'s `handleUpgrade()`,
run right after a sign-in completes, only ever called `refreshCurrentUser()` (the
Firestore profile mirror) — never `refreshRole()`. So switching accounts *within a
running session* (sign out → sign in as admin, no backgrounding in between) left `role`
stuck at whatever the previous, now-signed-out session had — `.learner`, since a guest
can never carry a creator/admin claim — and the only thing that ever fixed it was
backgrounding and reopening the app, which happens to also fire `refreshRole`. Fixed by
calling `environment.refreshRole(forceRefresh: true)` right after both `handleUpgrade`
outcomes (`.linked` and `.signedIntoExistingAccount`), not just on foreground.

**The tab bar's real root cause, found after two earlier attempts only patched the
symptom.** Both previous fixes (widening the immersion check to include `.loading`,
removing an `.animation()` modifier) targeted `FeedView`'s `isImmersed` computed
property — reasonable given what was visible, but neither was the actual bug.
`FeedPlayerPool.activate(index:)` only starts playback and sets `.playing` if a pooled
player slot *already exists* for that index; if none does, it silently returns and does
nothing. `FeedViewModel.onPageAppear()` was calling `activate(index:)` synchronously,
while the only thing that ever creates a slot — `prepare()` — was kicked off inside an
async `Task` in that same function. For a page reached by scrolling, this usually didn't
matter: the *previous* page's own prefetch window already covers the next one, so a slot
already exists by the time you scroll to it. But the very first page of any fresh feed
(cold launch, a topic pushed from Explore, the Profile Saved/Liked feed) has nothing
prepared yet — `activate()` found no slot, silently no-op'd, and the video sat there
`.loading` → `.paused` once its item became ready, never `.playing`. Since the tab bar's
visibility is driven directly off that state, it never hid — matching exactly what got
reported: the bar visible on open, and a video on screen that never actually started
until manually tapped. Fixed by making `onPageAppear()` call `playerPool.prepare()`
synchronously for the current index — `prepare()` itself is synchronous; only the
underlying network fetch is async — before calling `activate()`, so a slot is
guaranteed to exist every time, closing the race deterministically rather than relying
on prefetch timing to have won it.

### Swipe-to-navigate: replacing the video feed's back button with a two-rule gesture model

Enhancement request: remove the video feed's visible back chevron entirely, replace it
with an Instagram-style swipe, and layer swipe navigation across Learn/Explore/Profile
on top of that — a much bigger ask than it first sounded, so the model was confirmed
explicitly before writing any code (see the worked examples the user gave, reproduced
step for step by the two rules below) rather than guessed at.

**The model, confirmed with the user**: Learn, Explore, and Profile form a fixed ring.
- **Forward** (right-to-left) always advances one step through the ring — Learn →
  Explore → Profile — no matter how deep the current tab is pushed (a topic, a video).
  It never pops anything.
- **Backward** (left-to-right) pops one level of whatever's pushed on the current tab,
  if anything is; only once a tab is back at its own root does backward retreat one
  step through the ring.

Both stop dead at the ends (confirmed: no wraparound) rather than looping. The tab bar
stays visible and tappable throughout (confirmed: swipe is additive, not a replacement)
— exactly the same layering Snapchat and TikTok use. Scope (confirmed): the back-button
removal and swipe-to-pop apply to Explore's topic video feed *and* Profile's
Saved/Liked/due-for-review feeds (all three are just `FeedView` in non-`.mixed` mode),
but not the Learn tab's own mixed feed, which was never pushed onto anything to begin
with.

**Architecture**: `AppState` (already the home for cross-cutting, non-repository state)
gained `rootTab: RootTab` — moved out of `RootTabView`'s local `@State` so screens
pushed several levels deep can drive it directly without threading it through every
intermediate initializer. `RootTab` gained `nextInRing`/`previousInRing`, stepping a
fixed `[.learn, .explore, .profile]` array and returning `nil` at either end. A new
`RingSwipeNavigation` view modifier (`Shui/Sources/Views/RingSwipeNavigation.swift`)
implements the two rules as one direction-locked `DragGesture` (`.simultaneousGesture`,
so it never competes with a feed's own vertical video-paging scroll for the same touch)
and is attached with `isRoot: true` to each tab's own root content (`ExploreView`,
`ProfileView`, and `FeedView` in `.mixed` mode) and `isRoot: false` to everything pushed
on top of Explore or Profile (`CategoryPageView`, `TopicPageView`, and `FeedView` in
`.topic`/`.videoList` mode) — the same modifier and rules everywhere, no per-screen
special-casing. `FeedPageView.topBar` lost its back button and progress-pill spacer
layout entirely; the pill is just centered now.

**Known real-device risks, flagged rather than silently assumed away** — this sandbox
has no Swift compiler or device to test gestures against: the drag-distance and
direction-lock thresholds (60pt horizontal, 1.5× the vertical distance) are a starting
point that needs real tuning; and `CategoryPageView`/`TopicPageView` still show the
standard system nav bar (their own back button wasn't asked to be removed), so their
existing native edge-swipe-to-pop gesture and this new full-screen `DragGesture` both
listen for backward swipes starting right at the left edge — worth watching for on a
real device, though `simultaneousGesture` combined with the interactive pop gesture is
a well-established combination elsewhere, not a novel risk.

### The tab bar bug, a fourth time — and this time root-caused to the swipe feature itself

A screen recording of a genuine cold launch (force-quit, relaunch) showed the video
playing — content visibly advancing frame to frame — with the tab bar fully visible the
entire time, never hiding. Confirmed across multiple frames, not a loading-phase
artifact: this is a real, reproducing bug, and specifically only on a true cold launch,
never after just backgrounding and foregrounding.

The one thing that changed in this exact area since it last worked: the swipe-
navigation commit above moved `TabView`'s `selection` binding from `RootTabView`'s own
local `@State` to `appState.rootTab`, an `@EnvironmentObject`-sourced `@Published`
property, so screens pushed deep inside Explore/Profile could also drive it. That's the
leading suspect — SwiftUI's `.toolbar(for: .tabBar)` bridging to the underlying
`UITabBarController` has already needed two earlier rounds of fixes in this exact spot
this session (the `.loading`-state widening, the `objectWillChange` forwarding fix), so
a third timing-sensitive regression here, specifically only reproducing on the slower,
more asynchronous cold-launch path, is plausible. Rather than dig for definitive proof
this sandbox has no device to actually obtain, the fix is a cheap, low-risk revert:
`TabView` binds back to a local `@State` exactly as before, synced both directions with
`appState.rootTab` via `.onChange` so tapping a tab icon and swiping can never drift out
of step — `appState.rootTab` stays the thing every swipe gesture actually reads and
writes, unchanged.

### Swipe navigation, take two: a live, finger-tracking drag instead of gesture-then-jump

Enhancement request: make the swipe feel like Instagram's — content visibly follows the
finger while dragging, not a discrete gesture that's evaluated only once released and
then jumps. The original `RingSwipeNavigation` only ever inspected `DragGesture`'s
`.onEnded` value, computed a decision, and applied it instantly — functionally correct
but visually a snap-cut, not a drag.

Rewritten to track `.onChanged` too: an `offset` `@State` value is set directly (no
animation wrapper) to the live horizontal translation on every gesture update, so
content is glued to the touch with no lag. Releasing short of a 90pt commit threshold
springs the offset back to 0 (`.interactiveSpring`); releasing past it finishes the
slide the rest of the way off-screen (a fixed 600pt — comfortably past any real device
width, so it never needs to know the actual screen size) using
`withAnimation(_:completionCriteria:completion:)`, and only *after* that animation
genuinely completes does the real navigation change (`appState.rootTab = next`, or
`dismiss()`) fire and reset the offset — avoiding any guessed, hand-tuned delay between
the visual slide and the real state change landing underneath it.

Dragging in a direction with nothing to go to (past Profile, back past Learn) now does
nothing at all rather than a rubber-band tug that would visually promise a destination
that doesn't exist — checked live, per `.onChanged` frame, since a drag can reverse
direction mid-gesture.

**Deliberate scope cut, stated plainly rather than silently under-delivered**: this
makes the *current* screen follow the finger and animate off; it does not render a live
peek of the destination screen sliding in from the opposite edge the way a true
Instagram/TikTok transition does. Building that properly — either a fully custom paging
container (loses `TabView`'s native, already-correct safe-area/tab-bar behavior, a
nontrivial rebuild with real regression risk across every screen that reads
`safeAreaInsets`) or `TabView`'s native `.page` style (which removes the standard tab
bar entirely and would still fight the very real gesture-conflict problem of two
different native horizontal-pan recognizers — `.page`'s own paging gesture and
`NavigationStack`'s interactive pop gesture — both wanting the same touch at different
depths of the view hierarchy) — is real, further work with real risk, not something to
attempt blind with no device or compiler to verify against. Worth reconsidering once the
current version has been felt on a real device.

**Attempted and reverted: replacing `TabView` with a custom pager for the live peek
described above.** Built it (three ring tabs as live siblings in one `HStack`, a
hand-drawn bottom bar via `.safeAreaInset(edge: .bottom)`, `appState.rootDragOffset`
shared between the swipe gesture and the pager's own layout) — it worked, but the
hand-drawn tab bar didn't visually match iOS's native "Liquid Glass" tab bar style, and
matching that by hand with no device to actually see it on was too high-risk a bet to
keep iterating on blind. Reverted in full back to this entry's version (native `TabView`,
no live peek, still a real 1:1 finger-tracking swipe) rather than gamble a second round of
custom-bar styling nobody could verify. If the live peek becomes worth pursuing again, the
`git revert`'s parent commit has the working implementation to resume from.

## Phase 6 — Web dashboard

### Goal

`prompts/phase-06-web-dashboard.md`: a second client — Vite + React + TypeScript in
`web/` — over the exact same `shui-prod` Firebase backend the iOS app uses. No new data
model, no new privileged path; every write goes through the same Cloud Functions and
Firestore rules as the phone. What the phone can't do comfortably: long descriptions
with a real keyboard, batch video upload, a reports queue, per-question miss-rate
analytics.

### 6.1 — Scaffold

Project structure, tooling, theme port, and Firebase JS SDK wiring — nothing else yet.
Broken into its own sub-phase (matching Phase 5's 5.1–5.9 pattern) since this is one of
the largest single builds in the project: seven real screens against one shared spec,
in a stack this codebase hasn't touched before now.

**A genuinely different verification story than every Swift phase so far.** This
sandbox has no Xcode/Swift compiler, so every prior phase's Swift half has only ever
been checked by hand (brace balance, manual symbol cross-referencing) and actually
proven correct only once the user built it on a real Mac. The web dashboard is
different: this sandbox *does* have Node/npm, so `tsc`, ESLint, and a real production
`vite build` all ran for real during this sub-phase — and the pre-installed headless
Chromium loaded the actual dev server and screenshotted it, confirming zero console
errors and that the ported color palette renders correctly, not just that the code
compiles. Real verification, not the best-available substitute for it.

**What got built**: `web/` as a standalone npm package (not a workspace member of
`functions/` — the existing repo has no workspace tooling, and standing one up now was
judged more invasive than this scaffold needs; see `web/README.md` for the explicit
zod-version tradeoff that decision implies). Vite + React 19 + TypeScript 6 (not the
newer TypeScript 7 — confirmed via a real `npm install` failure that `typescript-eslint`
doesn't support it yet) + Tailwind v4, wired to `shui-prod` via the Firebase JS SDK.
`src/theme.ts` and `index.css`'s `@theme` block both port `ThemePalettes.swift`'s and
`Theme.swift`'s tokens by hand — necessarily duplicated between the two, since
Tailwind v4's CSS-first config can't import a `.ts` module; visually confirmed correct
via the Chromium screenshot above.

**Two real, disclosed `react-router` vulnerabilities were investigated and left
unaddressed on purpose**, not ignored — both are scoped to React Router's RSC
("framework") mode, which this plain client-rendered `BrowserRouter` SPA doesn't use at
all. `npm audit fix`'s suggested downgrade was actually tried and rejected: it
reintroduced nine *other*, worse disclosed vulnerabilities (open redirects, XSS, DoS)
that later releases had already fixed — a strictly worse trade for a fix that doesn't
even apply to how this app uses the library. Documented in `web/README.md` as something
to revisit on the next routine dependency update, not a permanent decision.

**What still needs the user's own action, not something this sandbox can do**:
registering a Web app for `shui-prod` in the Firebase console (produces the config
`web/.env` needs — a public client config, not a secret, same status as
`GoogleService-Info.plist`) and, later in 6.10, creating the Firebase Hosting site and
GitHub Action deploy secrets. `web/README.md` documents exactly what to fill in.

Next: 6.2 (auth + role gating), then the seven screens themselves.

## Phase 7 — Lessons on demand

`prompts/phase-07-lessons-on-demand.md`: the shareholder pivot. GolpoAI-backed
on-demand video lessons, a four-tier credit economy (Siltstone/Obsidian/Alabaster/
Pyramidion) billed through Apple In-App Purchase, a new Social tab replacing Learn,
and a self-serve developer API. Built as 6 backend slices plus one large iOS slice,
each a real commit.

### Backend — Slices 1–6

- **Slice 1**: schema/rules/tiers/credit ledger. `users/{uid}/private/wallet` (owner-
  read, Function-write) rather than fields on the public `users/{uid}` doc — a real
  security bug caught before it shipped. Nanodollar-precision math throughout so
  summing thousands of tiny per-call AI costs never drifts. A real bug found and fixed
  during this slice: `computeLikeRefund`'s cumulative case let an unlike-then-relike
  cycle re-cross an already-paid threshold and double-credit; fixed with a `Math.max`
  high-water mark and a regression test.
- **Slice 2**: the generation pipeline — one Claude call produces script + quiz +
  category together, GolpoAI renders the clean master, Shui burns its own watermark
  as a post-process (never GolpoAI's `custom_logo`) so one render serves every tier
  and a later upgrade retroactively unlocks clean downloads for free. A popular-topic
  cache keyed on normalized-topic + `timing` for cost savings.
- **Slice 3**: Apple IAP, not Stripe — caught and redirected before any Stripe code
  was written, since App Store Review Guideline 3.1.1 requires IAP for in-app digital
  goods. `appAccountToken` (minted once per user) is the only way an Apple transaction
  ties back to a Shui uid; `appAccountTokens/{token}` is the reverse-lookup collection
  that makes that work. Real Apple root certs committed (one fetched cert turned out
  already expired, caught via `openssl x509 -noout -dates` before committing it).
  `verifyAndApplyPurchase` (fast path) + `appStoreServerNotifications` webhook
  (durable backstop) both exist; `REFUND`/`REVOKE` reversal is deliberately NOT
  implemented — reversing a grant out of a pooled, already-possibly-spent balance
  isn't a small addition, flagged in a comment rather than shipped half-correct.
- **Slice 4**: tier-aware AI tutor — no daily cap, a per-tier dollar cost cap instead,
  auto-downgrade from Sonnet to Haiku at 70% of the cap spent, prompt caching (real
  cache-write/cache-read pricing, with the honest caveat that Haiku's 4096-token cache
  minimum means most Free/Siltstone traffic won't actually cache). Required upgrading
  `@anthropic-ai/sdk` from a badly stale 0.32.1 — it was missing `cache_control` and
  the cache-usage fields from its TypeScript types entirely.
- **Slice 5**: Social tab backend — a Function-maintained `socialScore` trigger
  (`log1p` of likes/comments/views, minus age decay), wired into `toggleLike` for
  Alabaster/Pyramidion's like-refunds.
- **Slice 6**: developer API — `apiKeys/{keyId}` (SHA-256 hash, raw key shown once),
  `createApiKey`/`listApiKeys`/`revokeApiKey` callables, `POST /v1/lessons` and
  `GET /v1/lessons/{id}` as a single `onRequest` function wrapping the exact same
  `runCreateOnDemandLesson`/`runCheckOnDemandLessonStatus` core the app uses — "one
  implementation, two entry points," not a second pipeline. A 20 req/hour per-key
  rate limit as a circuit breaker. Versioned reference at
  `functions/docs/developer-api.md`.

All six slices: clean `tsc`, full unit suite (124/124 at the end of Slice 6), full
rules suite against the real Firestore emulator (90/90).

### iOS — Slice 7

Every screen `prompts/phase-07-lessons-on-demand.md` §9 calls for, built on a new
data layer (repositories following the exact hand-wired-callable pattern every
existing repository already uses — no generic call helper introduced):

- **Data layer**: `Video`/`Topic` models extended for on-demand lessons (`.generating`
  status; `playbackURL`/`durationSeconds`/`sizeBytes` become optional, since a
  generating lesson's doc has them `null`; `Topic.categoryId` becomes optional for the
  `personal-{uid}` topic). New `Wallet`, `ApiKeyInfo`, `TierInfo` (a display-only
  mirror of `tiers.ts` — a paid tier's *shown* price always comes from StoreKit's own
  `Product.displayPrice`, never a hardcoded cents value), `CreditTransaction` models.
  New `OnDemandLessonRepository`, `BillingRepository`, `ApiKeyRepository`.
- **Create** (`CreateLessonView`): "What do you want to learn today?", a stage
  machine (idle/generating/ready/failed) mirroring `VideoUploadFlowView`'s existing
  shape-changes-with-stage pattern, 3s polling, a cost preview read live from the
  wallet.
- **My Lessons**: reuses `CreatorVideoRow`/`StatusBadge` from the Creator topic
  editor (made `internal`, not `private`) rather than a second video-list view, per
  the phase spec's explicit instruction. Retry on a failed lesson, Share to Social on
  a ready unshared one.
- **Social tab**: replaces Learn as `RootTab`'s primary tab (`.learn` → `.social`
  across `AppState`/`RootTabView`/`Strings`). Category chips and search sit in a
  custom translucent overlay, not `.searchable` — `FeedView` hides the system nav bar
  unconditionally, which `.searchable` needs to render into. Reuses the exact same
  `FeedView`/quiz-card player Phase 2 built; `FeedView` gained an explicit
  `isTabRoot` override so a `.videoList`-mode feed can still anchor swipe-navigation
  as a real tab root. The old composed `FeedComposer`/`.mixed` review feed is
  untouched and still fully tested — just no longer wired to any tab; where
  spaced-repetition review surfaces next is an open product question this rename
  doesn't resolve.
- **Billing**: real StoreKit 2 (`Product.products`/`purchase`, `appAccountToken` read
  from the wallet, a `Transaction.updates` listener), live wallet balance via a
  Firestore listener, transaction history from `creditTransactions`.
- **Developer API**: create/list/revoke keys; the raw key is shown exactly once in an
  alert with a copy button.

**Two real backend bugs found while wiring the iOS layer against it**, both fixed:
`listApiKeys` was returning raw Firestore `Timestamp` objects, which don't survive
the callable-functions JSON boundary as something a client can parse — now converts
to ISO 8601 strings at the callable, matching `aiTutorMessage`'s existing convention
for `resetAt`. And `createOnDemandLesson` wrote `rawTopic` on the cache-hit branch
but not the real-generation branch, so `checkOnDemandLessonStatus`'s
`if (!generatedFromCache && rawTopic)` cache-write gate could never actually fire for
a fresh generation — the shared lesson cache (§5) was silently dead code since Slice 2
shipped. Both fixes verified against the full backend suite afterward.

**Next step for the user, same as every phase before this one:** `git pull`,
`xcodegen generate` (this sandbox has no Swift toolchain to run it here, same
"no Xcode" limitation noted at the top of Phase 6 above — so `project.pbxproj`, as
committed, still only reflects an early-phase snapshot of `Shui/Sources` until it's
regenerated). `project.yml`'s `sources: - path: Shui/Sources` already globs
everything Phase 7 added recursively, no `project.yml` changes needed for the new
Swift files themselves. The one thing this phase's new `Shui.storekit` file did need
— it sits outside every existing `sources:` path — is already handled: added to
`sources` with `buildPhase: none` (a project reference only, not compiled/bundled)
and wired into the `Shui` scheme's `run.storeKitConfiguration`, so a fresh
`xcodegen generate` also gets local StoreKit purchase testing working, not just a
build that compiles.

**What still needs the user's own action**: a real GolpoAI API subscription, Apple
Developer Program enrollment with the 4 IAP products
(`com.shui.app.topup.5`/`tier.{obsidian,alabaster,pyramidion}.monthly`) configured in
App Store Connect plus the App Store Server Notifications webhook URL, and the Xcode
project sync above — all three already in progress per the user's own account. Once
those exist: real end-to-end testing on a device is the next real milestone, the same
bar every phase before this one was held to.
