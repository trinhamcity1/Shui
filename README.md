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
and one prompt per phase.

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: strip the dead lesson engine, English-only, Firebase SDK, clean build | **done** |
| 1 | Firestore model, security rules, Cloud Functions, R2 upload pipeline, seed content | **backend done, Swift build unverified** |
| 2 | Vertical video feed + end-of-video quiz + playback | not started |
| 3 | Categories, topic pages, auth, profile, progress, likes, comments | not started |
| 4 | AI tutor: grounded chat + proactive retention checks | not started |
| 5 | In-app creator console: topics, uploads, quiz builder, publish controls | not started |
| 6 | Browser dashboard for bulk authoring | not started |

Phases 0–3 are the shippable core. Phase 4 is the differentiator. Phases 5–6 are what
make the app maintainable without touching code.

**The consumer app UI is still a shell.** Three tabs, each a placeholder naming the phase
that fills it in — Phase 2 is the first phase that puts real consumer-facing content on
screen. Phase 1 stood up the real backend (Firestore schema, security rules, Cloud
Functions, R2 upload pipeline) and the Swift repository layer that talks to it; the one
thing in `Sources/Views/` that calls into it is a debug-only fourth tab that proves the
upload pipeline works end to end (see below), not a consumer feature.

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
  `UserRepository`, `UploadRepository`; `AITutorRepository` is a protocol only until
  Phase 4). `AppEnvironment` holds one instance of each, injected once at the root.
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
`R2_PUBLIC_BASE_URL`. Set them once against the real project with:

```sh
firebase functions:secrets:set R2_ACCOUNT_ID
firebase functions:secrets:set R2_ACCESS_KEY_ID
firebase functions:secrets:set R2_SECRET_ACCESS_KEY
firebase functions:secrets:set R2_BUCKET
firebase functions:secrets:set R2_PUBLIC_BASE_URL
```

They're never required for emulator work — only for `firebase deploy`.

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
generator script. Topics, videos, and quizzes are authored in-app (Phase 5) or in the web
dashboard (Phase 6), stored in Firestore, with video in R2.

`scripts/seed_civics.ts` exists to bootstrap a fresh environment and for local emulator
work — not as a place to add content. It seeds the 11 categories and one topic, **U.S.
Citizenship Civics Test (2025)**, as `status: "pending"` video shells with real quizzes
attached but no footage — a creator uploads actual video against these shells later
(Phase 5).

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

- **The backend exists now, but nothing in the app UI calls it yet.** Phase 1 built the
  real Firestore schema, security rules, Cloud Functions, R2 upload pipeline, and the
  Swift repository layer — but `Sources/Views/` is still three placeholder tabs. Phase 3
  wires up real sign-in against this backend; Phase 2 is the first phase that reads from
  it.
- **The Swift side of Phase 1 hasn't been built on a real Mac yet** — there's no Xcode in
  the sandbox this was authored in. The backend (Cloud Functions, security rules) is
  self-verified by `npm test` against real emulators; the `Sources/Data/` repository
  layer is written against APIs verified individually but has not been compiled.
- **The AI tutor does not exist yet.** The previous keyword-matching "AI" was deleted.
  Phase 4 builds the real one, with all model calls behind a Cloud Function so no API key
  ships in the binary. `AITutorRepository` is a protocol only until then.
- **Time-sensitive civics questions are deliberately excluded** from the seeded content —
  the sitting President, Vice President, Speaker, Chief Justice, governing party, and the
  learner's own Senators, Representative, Governor, and state capital. The older version
  of this app shipped placeholder strings as the correct answers to those. A "your
  officials" feature is a real product decision, not a data-entry task.
- **Not built, deliberately:** push notifications, voice mode for the tutor, real
  full-text search, localization, StoreKit/paid tiers, server-side user blocking. See the
  end of [`prompts/phase-06-web-dashboard.md`](prompts/phase-06-web-dashboard.md) for the
  reasoning on each.
