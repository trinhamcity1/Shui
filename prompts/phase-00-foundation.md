# Phase 0 — Foundation: strip, correct, and get a clean build

Read `prompts/README.md` first, especially **Shared conventions** and **Where the repo
stands today**. Follow those conventions for the whole phase.

## Goal

Turn a half-migrated single-subject civics tutor into an empty, honest, compiling
shell for a general educational video platform. Nothing in this phase adds a user-
visible feature. Everything in it removes a lie, deletes something unreachable, or
installs a dependency later phases need.

Do not start Phase 1 until the app builds and launches clean.

## 1. Delete the dead lesson engine

All of the following is either unreachable from `RootTabView` or replaced by
streamed video. Delete the files outright — do not comment them out, do not leave
`// TODO: restore` markers.

```
Shui/Sources/Views/Lesson/SceneCanvasView.swift
Shui/Sources/Views/Lesson/SceneElementViews.swift
Shui/Sources/Views/Lesson/LessonPlayerView.swift
Shui/Sources/Views/Lesson/ChapterPickerView.swift
Shui/Sources/Views/Home/HomeView.swift
Shui/Sources/Views/SessionFlowView.swift
Shui/Sources/Views/SessionSummaryView.swift
Shui/Sources/Views/Feed/AccountSheets.swift          # simulated OAuth + fake tiers
Shui/Sources/ViewModels/HomeViewModel.swift
Shui/Sources/ViewModels/SessionViewModel.swift
Shui/Sources/ViewModels/LessonPlaybackViewModel.swift
Shui/Sources/LearningEngine/SessionPlanner.swift
Shui/Sources/Models/FallbackLessonBuilder.swift
Shui/Sources/Models/TutorCharacter.swift
Shui/Sources/Models/CurrentOfficialsConfig.swift
Shui/Sources/AI/RuleBasedTutorAI.swift
Shui/Sources/AI/RemoteLLMTutorAI.swift
Shui/Sources/AI/TutorAIService.swift
Shui/Sources/AI/SpeechNarrator.swift
Shui/Sources/Localization/L10n.swift
Shui/Sources/Localization/LocalizationManager.swift
Shui/Sources/Models/AppLanguage.swift
Shui/Sources/Models/SessionLog.swift
Shui/Sources/Persistence/ContentStore.swift
Shui/Sources/Persistence/ContentRepository.swift
Shui/Sources/Views/Character/                        # whole directory
ShuiTests/SessionPlannerTests.swift
ShuiTests/ContentStoreTests.swift
Shui/Resources/en.lproj/                             # whole directory
Shui/Resources/vi.lproj/                             # whole directory
Shui/Resources/Content/                              # whole directory
Shui/Resources/Videos/                               # ~10 MB of placeholder MP4s
scripts/placeholder_videos/                          # whole directory
scripts/generate_content.py
```

Also delete the untracked leftover `Histudy.xcodeproj/` directory, and remove
`CFBundleLocalizations` and the now-unused `TutorBackendURL` key from `Shui/Info.plist`.

**Preserve these** — later phases build on them:

| Keep | Change |
|------|--------|
| `SpacedRepetitionScheduler.swift` + its tests | Move to `Sources/Learning/`. Drop the `QuestionProgress` SwiftData dependency: make `schedule` a pure function over a `ReviewState` value type (`easeFactor`, `intervalDays`, `repetitions`, `dueDate`) returning a new `ReviewState`. Keep the SM-2 math and all existing test assertions. |
| `QuizGrading.swift` | Move to `Sources/Learning/`. Keep `QuizGrader.isCorrect`. Delete `QuizOptionBuilder` entirely — distractors are now authored by the creator, not synthesized from other questions. Keep `QuizGradingTests` for the grader, delete the option-builder tests. |
| `VideoPlaybackController.swift`, `VideoPlayerLayerView.swift` | Move to `Sources/Playback/`. Keep as-is for now; Phase 2 extends them. |
| `Theme.swift` | Keep `Theme.shell` tokens, `ShuiPillButtonStyle`, `ShuiCardStyle`, the `Color(hex:)` initializer. Delete `Theme.scene` (whiteboard-only). |
| `scripts/sources/official_2025_civics.{py,json}` | Untouched. Phase 1 seeds from this. |
| `scripts/upload_videos_to_r2.py` | Keep as a one-off admin utility; Phase 1 supersedes it for app-driven uploads. |

## 2. Retire the local content model

Delete `CivicsQuestion`, `QuestionCategory`, `LessonScript`, `SceneAction`,
`NarrationBeat`, `SceneListItem`, `LessonStyle`, `USRegion`, `BilingualLine`,
`SubscriptionTier`, `AuthProvider`, `DynamicAnswerType`, and the dynamic-answer
resolution machinery. There is no bundled content anymore and no freemium tier —
subject-matter models are defined against the Firestore schema in Phase 1.

Keep `PersistenceController` but reduce it to a local **cache and offline queue**
only: `LessonComment` and `TutorChatMessage` become local mirrors of server data,
never the source of truth. Strip `UserProfile` down to device-local preferences
(`hasCompletedOnboarding`, selected interests, last-opened topic) — identity,
progress, streaks, and role now live in Firebase.

Delete `QuestionProgress` as a SwiftData model. Progress moves to Firestore in
Phase 1.

## 3. English only

There is no localization layer. Replace every `L10n.someKey.localized` call site with
either a plain literal or a `static let` in a new `Sources/Support/Strings.swift`.
Remove all `textVI` / `nameVI` / `titleVI` / `explanationVI` field pairs from any
model that survives — keep the single English field and drop the `EN` suffix.

Do not add `NSLocalizedString`, do not keep an empty `Base.lproj`, do not leave a
`language` field on the user profile "for later."

## 4. Wire up the Firebase SDK

Add to `project.yml` as a Swift Package dependency:

```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    minVersion: 11.0.0
```

Link these products to the `Shui` target: `FirebaseAuth`, `FirebaseFirestore`,
`FirebaseFunctions`, `FirebaseAnalytics`. Do **not** add `FirebaseStorage` — video
lives in R2.

Confirm `Shui/App/GoogleService-Info.plist` is a member of the app target's resources
(it is under `Shui/App`, which `project.yml` already includes as a source path — verify
it lands in Copy Bundle Resources after `xcodegen generate`).

Call `FirebaseApp.configure()` in a `UIApplicationDelegateAdaptor` or an `init()` on
`ShuiApp` before any other Firebase use. Enable Firestore local persistence and set
`isPersistenceEnabled = true` with unlimited cache size.

Add `Sources/Support/FirebaseBootstrap.swift` that performs configuration and exposes
`Firestore.firestore()`, `Auth.auth()`, and `Functions.functions()` behind small
accessors so no other file imports Firebase directly except the repository layer.

### Security chore, do it now

The committed `GoogleService-Info.plist` API key is unrestricted. In the Google Cloud
console, restrict that key to the iOS bundle ID `com.shui.app` and to the Firebase
APIs the app actually uses. Firebase iOS client keys are not secrets, so committing
the plist is fine — an unrestricted key is not. Note the restriction in the README so
the next person doesn't undo it.

Add to `.gitignore`: `*.env`, `.firebase/`, `firebase-debug.log`,
`functions/node_modules/`, `serviceAccountKey*.json`, `*-service-account.json`.

## 5. Reduce the app shell to a stub that runs

`RootTabView` becomes three tabs with placeholder content — Phases 2, 3, and 5 fill
them in:

- **Learn** (`play.rectangle.fill`) — will host the video feed
- **Explore** (`square.grid.2x2.fill`) — will host categories and topics
- **Profile** (`person.crop.circle.fill`) — will host progress, likes, settings

`RootView` drops the `.id(localization.currentLanguage)` re-render hack and the
onboarding gate for now; Phase 3 reintroduces onboarding once there are interests to
pick.

Each placeholder is a single centered `Text("Coming in phase N")`. The point is a
launchable app, not a mockup.

## 6. Rewrite `README.md` from scratch

The current README documents an app that no longer exists. Replace it with a short,
accurate document:

- What Shui is now: an educational short-video platform, English, iOS 17+
- Architecture: SwiftUI + MVVM + repositories; Firebase Auth/Firestore/Functions;
  Cloudflare R2 for video
- Setup: `brew install xcodegen`, `xcodegen generate`, `open Shui.xcodeproj`, run
- Firebase setup: which project, which Auth providers, how to run the emulator suite
- Where content comes from: **the creator console, not the repo.** State plainly that
  there is no bundled content generator anymore.
- A "Status" section listing which phases are done, kept honest as phases land
- Keep the honesty tone of the old README about what's simulated vs. real. Drop every
  claim that is no longer true: bundled videos, no backend, procedural whiteboard
  rendering, Vietnamese explanations, freemium tiers, the 100-question bank.

Point `prompts/README.md` from the main README so the build plan is discoverable.

## 7. Verify

Do not report this phase complete until all of these hold:

1. `xcodegen generate` succeeds; `Shui.xcodeproj` regenerated and committed.
2. `xcodebuild -scheme Shui -destination 'platform=iOS Simulator,name=iPhone 15'
   build` succeeds with zero errors. **This is the first time this codebase has ever
   been compiled — expect real errors and fix them properly rather than deleting code
   to silence them.** Report any signature mismatches you had to resolve.
3. The app launches in the simulator, shows three tabs, logs a successful
   `FirebaseApp.configure()`, and produces no red console output.
4. `xcodebuild test -scheme Shui` passes — the surviving SM-2 and grader tests only.
5. `git grep -i "vietnam\|textVI\|nameVI\|lproj\|L10n\|localized\|SceneAction\|FallbackLesson\|SessionPlanner\|current_officials"` returns nothing outside `prompts/` and `scripts/sources/`.
6. `du -sh Shui/Resources` is under 1 MB.

## Out of scope for Phase 0

No Firestore schema, no security rules, no Cloud Functions, no real screens, no auth
UI, no content seeding. Phase 1 does all of that. If you find yourself designing a
data model here, stop — you're in the wrong phase.
