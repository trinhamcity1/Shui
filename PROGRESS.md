# Shui — Build Progress & Decision Log

A running record of what's been built, why, and what broke along the way. The
phase plan itself lives in [`prompts/README.md`](prompts/README.md); this file
is the narrative of actually executing it — read it if you're picking the
project back up and want context faster than re-reading every commit.

Updated as each phase progresses. Current state: **Phase 2 written and
pushed, not yet built/verified in real Xcode** (this sandbox has no Swift
compiler — see the Phase 2 section below for how it was self-checked
instead).

## Phase status

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: strip the dead lesson engine, English-only, Firebase SDK, clean build | ✅ Done |
| 1 | Firestore model, security rules, Cloud Functions, R2 upload pipeline, seed content | ✅ Done — verified end-to-end on the real `shui-prod` project |
| 2 | Vertical video feed + end-of-video quiz + playback | Written, pushed — awaiting Xcode build/test on the user's Mac |
| 3 | Categories, topic pages, auth, profile, progress, likes, comments | Not started |
| 4 | AI tutor: grounded chat + proactive retention checks | Not started |
| 5 | In-app creator console: topics, uploads, quiz builder, publish controls | Not started |
| 6 | Browser dashboard for bulk authoring | Not started |

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
being non-optional). **Next step for the user:** `git pull`, run
`xcodegen generate` (required — many new files were added under globbed
`Shui/Sources` and `ShuiTests` paths), build in Xcode, and report back
whatever the compiler finds.

## Phases 3–6

Not started.
