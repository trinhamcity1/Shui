# Shui

An educational short-video platform for iOS: TikTok's interaction model applied to
learning instead of to idle scrolling. Videos *are* the lessons, every lesson ends in a
quiz, learners pick subjects deliberately, and an AI tutor checks retention through
conversation.

English only. iPhone, portrait, iOS 17+.

**The product test every feature has to pass:** does this help someone learn, or does it
just keep them scrolling? No infinite algorithmic firehose, no streak guilt, no autoplay
past a quiz the learner hasn't engaged with. When knowledge retention and session
retention conflict, knowledge wins.

## Status

Being built in phases — see [`prompts/README.md`](prompts/README.md) for the full plan
and one prompt per phase, and [`PROGRESS.md`](PROGRESS.md) for a running log of what's
been built, verified, and debugged phase by phase.

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: strip the dead lesson engine, English-only, Firebase SDK, clean build | **done** |
| 1 | Firestore model, security rules, Cloud Functions, R2 upload pipeline, seed content | **done — verified end-to-end against the real deployed backend** |
| 2 | Vertical video feed + end-of-video quiz + playback | **done — verified end-to-end against the real deployed backend** |
| 3 | Categories, topic pages, auth, profile, progress, likes, comments | **done — verified end-to-end against the real deployed backend, including several real live-testing bug fixes** |
| 4 | AI tutor: grounded chat + proactive retention checks | **done — verified end-to-end against the real deployed backend and a real model, with one known accepted limitation (see Honest notes)** |
| 5 | In-app creator console: topics, uploads, quiz builder, publish controls | **done — backend verified (`tsc`, unit tests, rules suite), live-tested extensively on a real device across many rounds (topic editor, upload flow, quiz builder, publish gates, admin surface), real bugs found and fixed** |
| 6 | Browser dashboard for bulk authoring | **in progress — scaffold up (Vite + React + Tailwind reading the app's own palette, Firebase JS SDK wired), auth/role gating and the real screens next** |
| 7 | Lessons on demand: a learner types a topic, gets a personal video + quiz via Shui-WG | **spec written (`prompts/phase-07-lessons-on-demand.md`), not yet built** |

Phases 0–3 are the shippable core. Phase 4 is the differentiator. Phases 5–6 are what
make the app maintainable without touching code. Phase 7 is the shareholder-directed
pivot from a purely curated feed to lessons on demand.

**Creator mode is real as of Phase 5** — Settings → Creator, visible only to a `creator`
or `admin` role claim. A dashboard that leads with what's blocking each draft, a topic
editor with drag-reorder and an inline publish checklist mirroring the server's gate, a
video upload flow that inspects/trims/transcodes locally before uploading with real byte
progress, a quiz builder that validates exactly what `saveQuiz` validates and previews
through the genuine feed quiz card, optional AI-drafted questions, and an admin surface
for the reports queue, roles, and categories. Long-form edits are mirrored to local
storage as you type and offered back on reopen.

**The Learn tab is real as of Phase 2**, confirmed working end-to-end on the real deployed
backend — a full-screen vertical video feed with pooled `AVPlayer` playback, the
due-review/continue-topic/new-in-interests/everything-else ordering algorithm, an
end-of-video quiz card (server-graded only), view tracking, and an offline quiz-attempt
retry queue. See [`PROGRESS.md`](PROGRESS.md)'s Phase 2 section for the debugging history
(a missing Firestore composite index, a stale-feed refresh bug, and how they were found).

**Explore, Profile, real auth, and Comments are real as of Phase 3** — guest-first
anonymous sign-in, Sign in with Apple and email, the 3-level Explore tab (categories →
category page → topic page) with topic search, a Profile tab with progress-by-subject and
liked videos, account deletion, one-level-threaded comments with likes/edit/delete/report,
and `shui://` deep links. Also new this phase: a semantic, WCAG AA-verified color system
(`ThemePalette`/`AppTheme`) replacing the old ad-hoc theme constants — see
[`PROGRESS.md`](PROGRESS.md)'s Phase 3 section for what that caught (two real,
already-shipped contrast bugs) and the rest of the phase's verification, including a real
`tsc` build and a 69-test Firestore emulator run against every backend change. Phase 3 was
then live-tested end to end on a real device across several rounds — see PROGRESS.md for
the real bugs that surfaced only under live testing (a guest feed permission denial from a
security-rule/query mismatch, a stale-environment SwiftUI bug that broke the feed's back
button, a missing Sign In with Apple entitlement) and how each was root-caused and fixed.

**The AI tutor is real as of Phase 4** — a `Discuss` / `Quiz me` mode toggle over one
grounded chat thread per video (title, description, transcript when one exists, quiz,
this learner's own attempt history, and recent thread history assembled server-side,
never client-side), streamed token by token via a Firestore-document listener rather than
raw SSE (simpler and more reliable on iOS, an explicit call the phase spec leaves open),
rate-limited per user, and a conversational "missed" verdict pulls that video's review
date forward through the same SM-2 scheduler quiz answers already use. See
[`PROGRESS.md`](PROGRESS.md)'s Phase 4 section for the real scope calls made along the
way — most notably, real speech-to-text transcript auto-generation was deliberately not
built (it needs its own provider decision and API key, and the spec's honest-degradation
path — the tutor opens by saying so and falls back to the multiple-choice quiz — is fully
built and is what every video in this app actually exercises today, since nothing has a
transcript yet).

## Architecture

SwiftUI + MVVM with a repository layer.

```
Shui/
  App/              ShuiApp (entry point), AppState, GoogleService-Info.plist
  Sources/
    Data/           Repository layer — the only place allowed to import Firebase
      Models/       Codable structs mirroring the Firestore schema
    Learning/       SM-2 review scheduling, quiz grading
    Playback/       AVPlayerLayer-backed chrome-less video playback
    Models/         Local-cache SwiftData models
    Persistence/    PersistenceController — local prefs, read cache, offline queue
    Support/        FirebaseBootstrap, Strings
    Theme/          Design tokens (mirrored by the web dashboard in Phase 6)
    Views/          SwiftUI, organized by feature
      Debug/        #if DEBUG-only screens, never shipped in release
  Resources/        Assets.xcassets only — no bundled content
ShuiTests/          Unit tests for pure logic
functions/          Cloud Functions (TypeScript, 2nd gen) — callables, triggers, schemas
firestore.rules     Security rules (deny-by-default)
firestore.indexes.json
prompts/            One build prompt per phase
scripts/            Admin utilities and content sources (own package.json — see below)
```

Rules that later phases depend on:

- **Views never touch Firestore, R2, or `URLSession` directly.** Everything goes through
  a repository protocol with a live implementation and an in-memory fake for tests and
  previews — see `Sources/Data/` (`CategoryRepository`, `TopicRepository`,
  `VideoRepository`, `QuizRepository`, `ProgressRepository`, `SocialRepository`,
  `UserRepository`, `UploadRepository`, `AuthRepository`, `AITutorRepository`).
  `AppEnvironment` holds one instance of each, injected
  once at the root, plus a reactive `currentUser` the whole app reads instead of each
  screen fetching its own snapshot.
- **Firebase imports are confined** to `Sources/Data/` and `Support/FirebaseBootstrap.swift`.
  `git grep "import Firebase"` outside those must return nothing.
- Async/await throughout. No completion handlers; no Combine except where SwiftUI
  requires `ObservableObject`.
- One `@MainActor` ViewModel per screen.
- **The client never grades a quiz or sees a correct answer ahead of time.**
  `videos/{id}/quiz/current` (public) holds prompts and options; the sibling
  `quiz/answers` document (owner/admin read only) holds `correctOptionIds` and
  `explanation`. Grading happens in the `submitQuizAttempt` Cloud Function.

### Backend

Firebase project `shui-prod`.

- **Auth** — Sign in with Apple + email/password, both enabled. Anonymous auth for guest
  browsing, upgraded via account linking.
- **Firestore** — all structured data: categories, topics, video metadata, quizzes,
  comments, progress, roles. Local persistence enabled.
- **Cloud Functions** (TypeScript, 2nd gen) — anything needing a secret or that must not
  be trusted to the client: R2 upload signing, counter maintenance, quiz grading, the AI
  tutor proxy, role assignment.
- **No Firebase Storage.** Video lives in Cloudflare R2.

### Video storage

Cloudflare R2, bucket `shui-videos`, public base
`https://pub-29f895ffbdcf49779204f67d1a69af9b.r2.dev`.

Uploads go direct from client to R2 using a presigned URL minted by a Cloud Function. R2
access keys live in Function secrets and never in the app, the repo, or Firestore.

## Setup

```sh
brew install xcodegen
xcodegen generate
open Shui.xcodeproj
```

Never hand-edit `Shui.xcodeproj` — edit `project.yml`, re-run `xcodegen generate`, and
commit both. The Firebase SDK resolves as a Swift Package on first open, which takes a
few minutes.

### Firebase

`Shui/App/GoogleService-Info.plist` is committed. Firebase iOS client configs are not
secrets — they identify the project, they don't grant access; access is controlled by
security rules and Auth.

> **The Google Cloud API key in that plist must stay restricted to the iOS bundle ID
> `com.shui.app` and to the Firebase APIs the app actually uses.** An unrestricted key is
> a real problem even though the plist itself is public. If you regenerate the key or
> create a new one, re-apply the restriction.

### Cloud Functions and the emulator suite

```sh
cd functions
npm install
npm run build      # tsc
npm test           # unit tests, then a Firestore-rules suite against the emulator
npm run emulate    # Firestore + Auth + Functions, with the Emulator UI on :4000
```

`npm test` runs two things: `test:functions` (plain Jest — SM-2/mastery/streak math, quiz
validation) and `test:rules` (`firebase emulators:exec` wrapping a Jest suite that loads
`firestore.rules` into a real Firestore emulator and asserts both the allowed and the
denied path for every row in the rules table below). Both need no Firebase login; the
emulator doesn't talk to any real project.

The app points at the emulator when launched with `-useFirebaseEmulator` (see
`ShuiApp.swift`'s `AppDelegate`) — add that as a launch argument on the scheme for
debug-only runs against `npm run emulate`.

A debug-only fourth tab, `DebugUploadPipelineView` (`#if DEBUG`, deleted or replaced once
Phase 2 has a real upload flow), exercises §8.4 of the phase doc end to end: sign in with
an account `bootstrap-admin.ts` granted `creator`/`admin`, pick a local video file, and
watch it go through `createVideoUpload` → a direct PUT to R2 → `finalizeVideoUpload` →
playback from `playbackURL` in `AVPlayer`. It needs a real device or simulator and real
R2 secrets deployed — this hasn't been run yet.

### Secrets

R2 credentials are Cloud Functions secrets, never client config:
`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`,
`R2_PUBLIC_BASE_URL`. Set them once against the real project — get R2 values from
the Cloudflare dashboard (R2 → Manage API tokens → Create API token, scoped to the
`shui-videos` bucket):

```sh
cd functions
cp .secrets.local.env.example .secrets.local.env   # gitignored — fill in real values
npm run secrets:push                                # pushes all six in one go
```

`secrets:push` runs `scripts/set-secrets.sh`, which reads `.secrets.local.env` and
calls `firebase functions:secrets:set` for each of the six names (five R2 credentials
plus `AI_API_KEY`, the Phase 4 AI tutor's model provider key) — no manual
copy-pasting into interactive prompts, and no real values ever touch git. Re-run it
whenever a credential rotates; a function already deployed needs a fresh
`firebase deploy --only functions` afterward to pick up the new value. Secrets are
never required for emulator work — only for a real `firebase deploy`.

### Bootstrapping an admin and seeding the civics content

Both scripts live in `scripts/`, which has its own `package.json` (a standalone Node
project — it doesn't share `functions/node_modules`):

```sh
cd scripts
npm install
```

Grant the first admin claim (breaks the chicken-and-egg problem: the `assignRole`
callable itself requires an admin caller):

```sh
npm run bootstrap-admin -- <uid-or-email>
```

Then seed the 11 categories and the civics topic (idempotent — safe to re-run):

```sh
SEED_ADMIN_UID=<uid> npm run seed:civics
```

Against the emulator suite, wrap both in `firebase emulators:exec` from `functions/` so
nothing touches a real project — `npm run seed:local` does exactly that. Against a real
project, `bootstrap-admin.ts` needs `GOOGLE_APPLICATION_CREDENTIALS` pointing at a
service account key that is **never committed** (see `.gitignore`).

## Where content comes from

**The creator console, not the repo.** There is no bundled content and no content
generator script. Topics, videos, and quizzes are authored in-app — Settings → Creator,
real as of Phase 5 — stored in Firestore, with video in R2. Adding a topic, uploading and
trimming a video, writing its quiz, and publishing all happen on a phone with no code
change, no script, and no redeploy.

`scripts/seed_civics.ts` **exists only to bootstrap a fresh environment and for local
emulator work. Do not add new content to it** — that's what creator mode is for, and a
second authoring path that only runs from a developer's laptop is exactly what Phase 5
removed. It seeds the 11 categories and one topic, **U.S. Citizenship Civics Test
(2025)**, as `status: "pending"` video shells with real quizzes attached but no footage; a
creator uploads actual video against those shells from the app.

`scripts/sources/official_2025_civics.json` is a verbatim transcription of the current
official USCIS civics test (form M-1778 (09/25), 128 questions with accepted answers).
It's a source document, used once by the seed script.

## Testing

Unit tests cover pure logic — review scheduling, grading, feed ordering, validation —
on both sides of the SM-2 port (`Sources/Learning/` in Swift, `functions/src/lib/sm2.ts`
in TypeScript; the two must agree, and a parity test asserts the shared default ease
factor). Security rules get emulator tests, including a failing-path test per row of the
table in `firestore.rules`. No UI snapshot tests.

```sh
xcodebuild test -scheme Shui -destination 'platform=iOS Simulator,name=iPhone 15'
cd functions && npm test
```

This codebase was originally authored on Linux and went a long time without ever being
compiled. A green build is the minimum bar, not a formality.

## Honest notes

- **The AI tutor doesn't always attach its structured metadata — a known, accepted
  limitation.** Alongside its visible reply, the model is asked to append a delimited
  block carrying two things: the suggested-reply chips, and (in "Quiz me") a
  solid/shaky/missed verdict that pulls the video's review date forward through SM-2. Two
  real eval runs against `claude-sonnet-5` showed it sometimes omits that block, or leaves
  the verdict null, most often on ambiguous turns ("I don't know", partial answers) —
  strengthening the prompt wording narrowed but did not close this. **Blast radius is
  confined to the AI Tutor sheet**: when it happens, the chips row is empty and that one
  answer doesn't nudge the review schedule. Nothing crashes, no wrong data is written, and
  the in-feed quiz (a completely separate path) is unaffected. The real fix is structural —
  forcing the metadata through Anthropic's tool-use mechanism instead of a free-text
  delimiter the model has to remember — and is deliberately deferred, to be revisited as
  usage scales. Both runs and the full analysis are in `functions/src/ai/evals/README.md`.
- **Real speech-to-text transcript generation was deliberately not built.** The phase spec
  allows this — "if neither exists, ... degrade honestly" — and every video in this app
  today has no transcript anyway, so the degraded path (the tutor says so, and "Quiz me"
  falls back to the multiple-choice questions) is what actually gets exercised. Auto-
  transcription is real, separate follow-up work needing its own speech-to-text provider
  decision and API key, not an oversight.
- **Universal Links aren't functional yet** — the Associated Domains entitlement points at
  a placeholder domain (`example.com`) since no real domain exists. `shui://video/{id}` and
  `shui://topic/{id}` (custom URL scheme) work; the web-fallback half doesn't until a real
  domain is registered and serves an `apple-app-site-association` file.
- **Time-sensitive civics questions are deliberately excluded** from the seeded content —
  the sitting President, Vice President, Speaker, Chief Justice, governing party, and the
  learner's own Senators, Representative, Governor, and state capital. The older version
  of this app shipped placeholder strings as the correct answers to those. A "your
  officials" feature is a real product decision, not a data-entry task.
- **Not built, deliberately:** push notifications, voice mode for the tutor, real
  full-text search, localization, StoreKit/paid tiers, server-side user blocking. See the
  end of [`prompts/phase-06-web-dashboard.md`](prompts/phase-06-web-dashboard.md) for the
  reasoning on each.
