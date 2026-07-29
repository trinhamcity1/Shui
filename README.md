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
| 0 | Foundation: strip the dead lesson engine, English-only, Firebase SDK, clean build | **in progress** |
| 1 | Firestore model, security rules, Cloud Functions, R2 upload pipeline, seed content | not started |
| 2 | Vertical video feed + end-of-video quiz + playback | not started |
| 3 | Categories, topic pages, auth, profile, progress, likes, comments | not started |
| 4 | AI tutor: grounded chat + proactive retention checks | not started |
| 5 | In-app creator console: topics, uploads, quiz builder, publish controls | not started |
| 6 | Browser dashboard for bulk authoring | not started |

Phases 0–3 are the shippable core. Phase 4 is the differentiator. Phases 5–6 are what
make the app maintainable without touching code.

**Right now the app is a shell.** Three tabs, each a placeholder naming the phase that
fills it in. There is no feed, no auth, no content, and no backend wired up yet. That is
the intended end state of Phase 0 — an honest, compiling starting point rather than a
half-migrated app that lies about what works.

## Architecture

SwiftUI + MVVM with a repository layer.

```
Shui/
  App/              ShuiApp (entry point), AppState, GoogleService-Info.plist
  Sources/
    Learning/       SM-2 review scheduling, quiz grading
    Playback/       AVPlayerLayer-backed chrome-less video playback
    Models/         Local-cache SwiftData models
    Persistence/    PersistenceController — local prefs, read cache, offline queue
    Support/        FirebaseBootstrap, Strings
    Theme/          Design tokens (mirrored by the web dashboard in Phase 6)
    Views/          SwiftUI, organized by feature
  Resources/        Assets.xcassets only — no bundled content
ShuiTests/          Unit tests for pure logic
prompts/            One build prompt per phase
scripts/            Admin utilities and content sources
```

Rules that later phases depend on:

- **Views never touch Firestore, R2, or `URLSession` directly.** Everything goes through
  a repository protocol with a live implementation and an in-memory fake for tests and
  previews. Phase 1 adds `Sources/Data/`.
- **Firebase imports are confined** to `Sources/Data/` and `Support/FirebaseBootstrap.swift`.
  `git grep "import Firebase"` outside those must return nothing.
- Async/await throughout. No completion handlers; no Combine except where SwiftUI
  requires `ObservableObject`.
- One `@MainActor` ViewModel per screen.

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

Emulator suite (Phase 1 onward):

```sh
firebase emulators:start          # Firestore, Auth, Functions
```

Point the app at it by passing `-useFirebaseEmulator` as a launch argument in the Xcode
scheme (debug builds only).

## Where content comes from

**The creator console, not the repo.** There is no bundled content and no content
generator script. Topics, videos, and quizzes are authored in-app (Phase 5) or in the web
dashboard (Phase 6), stored in Firestore, with video in R2.

`scripts/seed_civics.ts` (Phase 1) exists to bootstrap a fresh environment and for local
emulator work — not as a place to add content.

`scripts/sources/official_2025_civics.json` is a verbatim transcription of the current
official USCIS civics test (form M-1778 (09/25), 128 questions with accepted answers).
It's a source document, used once by the seed script.

## Testing

Unit tests cover pure logic — review scheduling, grading, feed ordering, validation.
Security rules get emulator tests, including a failing-path test per rule. No UI snapshot
tests.

```sh
xcodebuild test -scheme Shui -destination 'platform=iOS Simulator,name=iPhone 15'
```

This codebase was originally authored on Linux and went a long time without ever being
compiled. A green build is the minimum bar, not a formality.

## Honest notes

- **Nothing is wired to a backend yet.** Phase 0 removed the simulated auth and fake
  subscription tiers rather than leaving them to be mistaken for real ones. Phase 1
  stands up Firestore and Functions; Phase 3 adds real sign-in.
- **The AI tutor does not exist yet.** The previous keyword-matching "AI" was deleted.
  Phase 4 builds the real one, with all model calls behind a Cloud Function so no API key
  ships in the binary.
- **Time-sensitive civics questions are deliberately excluded** from the seeded content —
  the sitting President, Vice President, Speaker, Chief Justice, governing party, and the
  learner's own Senators, Representative, Governor, and state capital. The older version
  of this app shipped placeholder strings as the correct answers to those. A "your
  officials" feature is a real product decision, not a data-entry task.
- **Not built, deliberately:** push notifications, voice mode for the tutor, real
  full-text search, localization, StoreKit/paid tiers, server-side user blocking. See the
  end of [`prompts/phase-06-web-dashboard.md`](prompts/phase-06-web-dashboard.md) for the
  reasoning on each.
