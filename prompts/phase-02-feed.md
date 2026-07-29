# Phase 2 — The feed: video lessons, playback, and the end-of-video quiz

Read `prompts/README.md` first. Phases 0–1 must be merged and building.

## Goal

Build the Learn tab: a full-screen vertical video feed that feels as smooth as TikTok,
where every video is a lesson and every lesson ends in a quiz. This is the core loop
and the screen people will judge the app on. Get the playback right before adding
anything decorative.

## 1. The loop, precisely

```
video plays full-screen (autoplay, looping muted? no — sound on, single play)
   ↓ video reaches the end
quiz card slides up over the paused final frame
   ↓ learner answers each question, sees whether they were right + why
result summary: score, pass/fail, "Swipe up for the next lesson" / "Replay"
   ↓
learner swipes up → next lesson    |    taps Replay → video restarts from 0
```

Behavior requirements, from the product brief:

- **Tap once anywhere on the video** → pause. Tap again → resume. Show a large play
  glyph while paused, fading after 1s. No scrub bar gesture in this phase, but the
  thin progress bar at the top is always visible and non-interactive.
- **Do not auto-advance.** When a video ends, the quiz appears and playback stops.
  The learner decides what happens next. Auto-advancing into the next video is the
  dopamine-treadmill behavior this app is explicitly not.
- **If the learner doesn't scroll**, the video does not loop by default — the quiz is
  the natural end state. Replay is an explicit action.
- **Scrolling away from an unanswered quiz is allowed.** Don't trap people. But record
  it: a skipped quiz sets `quizAttempts` unchanged and schedules the video for review
  sooner (Phase 1's SM-2 treats never-answered as due).
- **Scrolling back down** to a previously watched video shows it at its start with the
  quiz collapsed, ready to replay.
- Only the visible page plays. Scrolling away pauses immediately and releases nothing —
  the player is kept warm within the prefetch window.

## 2. Playback architecture

Rewrite `VideoPlaybackController` from Phase 0 into a proper feed player. The single
biggest source of jank in a video feed is creating and destroying `AVPlayer` instances
during a scroll, so don't.

**`FeedPlayerPool`** — an actor or `@MainActor` class owning a fixed ring of 3–4
`AVPlayer` instances, keyed by feed index:

- `prepare(index:)` creates an `AVURLAsset` + `AVPlayerItem` for indexes
  `current-1 … current+2` and loads them into pooled players.
- `activate(index:)` plays the pooled player for that index and pauses all others.
- Recycle the player that falls outside the window; never allocate per page.
- Set `automaticallyWaitsToMinimizeStalling = true` and
  `preferredForwardBufferDuration = 4` on each item.
- Observe `AVPlayerItem.status` and `isPlaybackLikelyToKeepUp`; expose a
  `PlaybackState` enum (`idle`, `loading`, `playing`, `paused`, `ended`, `failed(Error)`).
- Configure `AVAudioSession` once, category `.playback`, so audio plays with the app in
  the foreground and respects the silent switch appropriately for a video app.
- Handle interruptions (phone call, other app audio) and route changes.

**Prefetching.** In addition to warming players, prefetch the next two videos'
thumbnails so a stalled page shows a poster frame rather than black. Cancel prefetch
work for indexes that leave the window.

**Failure handling.** A video that fails to load shows a retry card with the video
title, not a black screen. One automatic retry, then manual. Log the failure to
Analytics with the video id.

## 3. Feed composition — what order, and why

`FeedViewModel` builds the page list from `VideoRepository` and `ProgressRepository`.
This is where the app's educational stance shows up. Order:

1. **Due for review** — videos whose `videoProgress.dueDate <= now`, soonest first.
   These are the ones the learner previously failed or hasn't been quizzed on.
2. **Continue the current topic** — unwatched videos from the topic with the most
   recent activity, in `order`.
3. **New in chosen interests** — unwatched public videos in the user's `interests`
   categories, newest first.
4. **Everything else public**, newest first.

Interleave rather than strictly concatenate: never place more than 3 review items in a
row, so a session doesn't open as a wall of past failures. Cap review items at 40% of
any 10-page window.

Load 10 pages at a time with cursor pagination; fetch the next batch when the learner
is 3 pages from the end. Deduplicate by video id across batches.

The feed is entered in two modes and `FeedViewModel` must support both:
- **Mixed feed** (Learn tab): the ordering above, across all interests.
- **Topic feed** (pushed from a topic page in Phase 3): only that topic's videos, in
  `order`, starting at a specified video. Same view, different source.

Write `FeedComposerTests` against the pure ordering function with fake progress data:
review-first, the 3-in-a-row cap, the 40% window cap, dedup, and stable ordering.

## 4. Screen layout

Full-bleed video with overlays. All overlays sit above a subtle bottom gradient scrim
so white text stays legible on any frame.

**Top:** thin progress bar (video position), and — only in topic mode — a small
"3 of 12" pill and a back chevron.

**Bottom left:** topic title (tappable → topic page), video title, and a truncated
description with a "more" affordance that opens the info sheet.

**Right rail**, bottom-aligned, vertically stacked, each a glyph with a count or label
beneath:

| Order | Glyph | Action |
|---|---|---|
| 1 | `heart.fill` | Like. Optimistic toggle, `likeCount` updates locally then reconciles. Requires a real account — guests get the sign-in sheet. |
| 2 | `bubble.right.fill` | Comments sheet (Phase 3). Shows `commentCount`. |
| 3 | `sparkles` | **AI** — opens the tutor (Phase 4). Label it "AI", not "Ask". |
| 4 | `arrowshape.turn.up.right.fill` | Share via `UIActivityViewController` with a deep link `shui://video/{videoId}` and a web fallback URL. |
| 5 | `bookmark.fill` | Save to "My list" — optional in this phase; include only if it's free to add given the like plumbing. |

In this phase, comments and AI open placeholder sheets that say which phase fills them
in. The rail's layout, hit targets (44pt minimum), and animation must be final.

**Haptics:** a light impact on like, a selection tick on quiz option tap, a success
notification on quiz pass. Nothing on scroll.

## 5. The quiz card

A sheet-like overlay that slides up over the paused last frame at ~70% height,
scrollable, with the video's final frame dimmed behind it.

Presentation rules:
- One question at a time, `orderIndex` order. Show "Question 2 of 3".
- Options are large tappable rows. Single-select when `requiredCorrectCount == 1`,
  multi-select up to the required count otherwise, with the count stated in the prompt
  area.
- Submit is disabled until exactly the required number is selected.
- On submit, call `submitQuizAttempt` for the whole quiz at the end — but reveal
  per-question correctness immediately from the callable's response. Simplest correct
  approach: submit each question as its own attempt is not allowed by the schema, so
  collect answers locally, submit once at the end, then walk the returned `results`
  array to animate each question's outcome in sequence. Do **not** grade on the client.
- Correct: green fill on the chosen option, checkmark, and the `explanation` text.
  Incorrect: red on the chosen option, green on the correct one, and the `explanation`.
  The explanation always shows, right or wrong — that's where the learning happens.
- After the last question: a result card with score, pass/fail against
  `passThreshold`, mastery delta for the topic, and two buttons: **Next lesson**
  (scrolls the feed up) and **Replay**.
- If a video has `hasQuiz == false`, skip the card entirely and show a compact
  "Lesson complete" strip with Next / Replay. Do not fabricate questions.

Offline: if `submitQuizAttempt` fails, keep the answers, show an inline retry, and
queue the attempt for resubmission. Never silently drop a completed quiz.

## 6. View tracking

Write a `viewEvents` document (`{ videoId, uid, watchedSeconds, completed, createdAt }`)
when a page is scrolled away from or the quiz opens — whichever comes first. Never
increment `videos.viewCount` from the client; Phase 1's hourly Function does that.

Call `markVideoCompleted` when watched ≥ 90%.

## 7. Empty and edge states

- **No videos at all** (fresh install, nothing published): a card explaining the app
  and a button to Explore. Not a spinner forever.
- **All caught up** (every video in interests watched): a card offering review of
  due items or a jump to Explore.
- **Guest**: everything works except like/comment/AI, each of which presents the
  sign-in sheet (Phase 3 builds it; stub it here).
- **Slow network**: poster frame + spinner, never a black page.

## 8. Accessibility

Every rail button has an accessibility label and value ("Like, 42 likes"). Quiz options
are buttons with `isSelected` traits. Support Dynamic Type up to XL in the quiz card
(the video overlay text may cap earlier). Respect Reduce Motion by cross-fading instead
of sliding the quiz card. VoiceOver must be able to complete a full lesson→quiz loop.

## 9. Verify

1. Scroll 30 pages quickly on a physical device or simulator: no dropped frames from
   player allocation, memory stable, at most 4 `AVPlayer` instances alive.
2. Tap-to-pause and tap-to-resume work on the first tap, every time.
3. A video that ends shows the quiz; nothing auto-advances.
4. Answering a quiz updates `videoProgress`, `topicProgress.masteryPercent`, and the
   `dueDate` in Firestore — verify in the emulator UI.
5. Failing a quiz makes that video reappear in a later feed load as a review item.
6. Skipping a quiz by scrolling records no attempt and still schedules review.
7. Airplane-mode mid-quiz: the attempt queues and submits on reconnect.
8. `FeedComposerTests` and quiz-state ViewModel tests pass.
9. VoiceOver completes one full loop.

## Out of scope

Comments UI, AI tutor, categories/Explore, profile, creator tools, sign-in UI beyond a
stub sheet.
