# Histudy — U.S. Citizenship Civics Tutor

A native iOS app that helps Vietnamese-speaking immigrants prepare for the
U.S. citizenship civics test in daily 5-10 minute sessions with an
AI-adaptive tutor character, "Ms. Lien" (Chị Liên).

This repo is the two-week MVP described in the product brief: **one
character, a solid 100-question bank, and a working end-to-end learning
loop** — lesson → quiz → adaptive scheduling — rather than a partially
wired-up version of the full long-term vision (100 fully produced videos,
a live backend, a second character). See **Scope decisions** below for what
that means concretely.

## Requirements

- Xcode 15+ (targets iOS 17, uses SwiftData + Swift Concurrency)

## Setup

`Histudy.xcodeproj` is committed to the repo, so you don't need XcodeGen
installed to open and run the app:

```bash
open Histudy.xcodeproj
```

Select the `Histudy` scheme and run on an iOS 17+ simulator or device.

`Histudy.xcodeproj` is generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and checked in as a
convenience. If you edit `project.yml` (add a target, change a build
setting), regenerate and commit the result:

```bash
brew install xcodegen   # one-time
xcodegen generate
```

> **This project was authored in a Linux container with no Xcode available**,
> so the Swift/SwiftUI/SwiftData app code itself has not been compiled —
> that fundamentally requires macOS. What *was* verified from this session:
> content JSON was validated against the Swift model shapes, localization
> keys were checked for 1:1 EN/VI parity, enum raw values were checked
> against JSON, and — since XcodeGen is pure Swift/Foundation with no Apple
> SDK dependency — a Swift 6.1 toolchain was installed and used to build
> XcodeGen from source right here and actually run `xcodegen generate`
> against `project.yml`, producing the real, valid `Histudy.xcodeproj` now
> committed in this repo (not hand-written). So the project file itself is
> known-good; **please still treat the first build of the Swift code in
> Xcode as the real smoke test**, not a formality. If something doesn't
> compile, it's most likely a small signature mismatch, not a structural
> problem — the codebase is organized so any one fix should be localized to
> a single file.

## Architecture

```
Histudy/
  App/              HistudyApp.swift (entry point), AppState (shared services)
  Resources/
    Content/         Bundled JSON: 100 questions, lesson scripts, categories,
                      state capitals, current officials, character dialogue
    en.lproj/vi.lproj Localizable.strings (UI chrome only, see below)
    Assets.xcassets   App icon slot + accent color (no character art needed)
  Sources/
    Models/          Codable content models + SwiftData models (UserProfile,
                      QuestionProgress, SessionLog)
    Persistence/      ContentStore (loads bundled JSON), PersistenceController
                      (SwiftData)
    LearningEngine/   SM-2 spaced repetition, session planner, quiz grading
    AI/               TutorAIService protocol + rule-based/remote impls,
                      SpeechNarrator (AVSpeechSynthesizer)
    Localization/     LocalizationManager (bundle-swizzle) + typed L10n keys
    ViewModels/        One per screen/flow
    Views/            SwiftUI, organized by feature
HistudyTests/          Unit tests for the learning engine + content integrity
scripts/
  generate_content.py  Generates everything under Resources/Content/ — the
                        100-question bank and lesson scripts are authored
                        here as structured Python data, not hand-typed JSON
```

`scripts/generate_content.py` is the source of truth for all bundled
content. If you need to edit a question, an explanation, or a lesson
script, edit that file and re-run `python3 scripts/generate_content.py`
rather than hand-editing the generated JSON.

## Scope decisions (read this before demoing or extending)

**100-question bank: fully real.** All 100 official USCIS civics
questions are included, each with its accepted English answer(s), a
Vietnamese explanation written with narrative/mnemonic context (not just a
translated fact), and a category matching USCIS's own grouping.

**Time-sensitive answers are not hard-coded.** Questions like "who is the
President now" or "who is the Speaker of the House" change over time, and
questions like "who is your Governor" or "your state's capital" depend on
where the learner lives. Baking in a specific name would silently go stale
in a way that actively misleads someone studying for a real interview. So:
- National officeholders (President, VP, Speaker, Chief Justice, President's
  party) are resolved from `current_officials.json`, which currently ships
  with placeholder strings and a `sourceNote` telling you to fill it in and
  verify against uscis.gov/house.gov/senate.gov before release.
- The learner's own Senators/Representative/Governor are entered once
  during onboarding (or by a preparer helping them) and stored locally.
- State capitals are static facts and are safely bundled (`state_capitals.json`).

**16 flagship lessons are hand-authored in the "whiteboard, narrative, not
just facts" style** described in the brief — e.g. the 50-stars/13-stripes
flag lesson walks through the five U.S. regions on a map, the same idea
called out in the product brief for teaching "50 states." Together they
cover 31 of the 100 questions. **The other 69 questions use an
auto-generated flashcard-style lesson** (`FallbackLessonBuilder`) built from
the question's own quick-fact and explanation text, so every one of the 100
questions has a narrated lesson + quiz today — just not all with the full
custom-animated treatment yet. Expanding coverage is additive: add an entry
to the `LESSONS` list in `generate_content.py`, nothing else changes.

**"Whiteboard animation" is rendered live in SwiftUI, not pre-rendered
video.** There was no way to produce 100 professionally animated video
files for this MVP. Instead, `SceneCanvasView` plays back a lesson's JSON
timeline as procedurally drawn scenes (a stylized 5-region U.S. map, city
pins, document/timeline/flag graphics, etc.) synced to on-device narration
via `AVSpeechSynthesizer`. This is a deliberate trade-off: it ships today
with no asset pipeline, it's trivially bilingual (swap the narration text,
nothing re-renders), and it's small (no video files in the app bundle) —
but it is not the same visual fidelity as a hand-animated video, and if you
later commission real animation, `LessonScript`/`SceneAction` would need a
video-backed lesson style alongside this one.

**Quizzes are multiple-choice, not free-text.** This grades unambiguously
on-device, keeps a 5-10 minute session fast, and doesn't penalize someone
still building English confidence for a typo. Distractors are drawn from
other questions in the same category.

**"AI-powered personalization" is a real spaced-repetition engine, not
marketing copy — but the in-character dialogue is rule-based, not an LLM,
by default.** `SpacedRepetitionScheduler` (SM-2) and `SessionPlanner`
concretely change which questions come up and in what order based on the
learner's actual performance — that's the adaptive part, and it works fully
offline. Ms. Lien's reactions ("that's right!", "let's look at that again")
come from `RuleBasedTutorAI`, a small pool of bilingual lines in
`character.json`, also fully offline. There's a `RemoteLLMTutorAI`
implementation ready to go if you want real generative dialogue — but it
deliberately expects a backend URL (`TutorBackendURL` in `Info.plist`) that
*you* operate, which holds the actual model API key server-side. An iOS
app should never embed an LLM API key directly (it can be extracted from
the shipped binary); wiring up generative dialogue safely is a follow-up
task, not something to bolt on by hard-coding a key into this codebase.

**No accounts, no server.** Everything — profile, progress, streaks,
session history — lives on-device via SwiftData. There's nothing to stand
up to run the MVP.

## What's explicitly out of scope for this MVP

- A second character, or character customization
- A real backend for the LLM tutor (the hook exists; the service doesn't)
- Hand-animated video assets
- App Store submission assets (real icon artwork, screenshots, privacy
  manifest beyond the minimum, TestFlight configuration)
- A legal/accuracy review of the civics content against uscis.gov — do this
  before any real user relies on this app for an actual interview

## Testing

`HistudyTests` covers the parts that are pure logic and worth locking down:
- `SpacedRepetitionSchedulerTests` — SM-2 math (interval growth, ease floor, due-date logic)
- `QuizGradingTests` — multiple-choice grading and distractor generation
- `SessionPlannerTests` — due-before-new ordering, time-budget behavior
- `ContentStoreTests` — the 100-question bank loads completely, every
  question resolves to a lesson, dynamic questions never ship a stale
  static answer

Run via ⌘U in Xcode, or `xcodebuild test -scheme Histudy -destination
'platform=iOS Simulator,name=iPhone 15'` from the command line.

## Roadmap (post-MVP)

1. Author remaining lesson scripts in `generate_content.py` to bring all
   100 questions up to the full narrative/whiteboard treatment.
2. Stand up the small backend `RemoteLLMTutorAI` expects, and point
   `TutorBackendURL` at it, for real generative tutor dialogue.
3. Content accuracy pass: verify all 100 answers and fill in
   `current_officials.json` against uscis.gov before shipping to real users.
4. A second character / character choice.
5. Push notifications for the daily reminder (not included — no
   notification scheduling code exists yet).
6. Real app icon and launch assets, TestFlight, App Store metadata.
