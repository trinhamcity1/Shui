# Phase 3 — Discovery, identity, and the social layer

Read `prompts/README.md` first. Phases 0–2 must be merged and building.

## Goal

Make the app deliberate rather than passive. A learner picks a subject, sees what's in
it, tracks their own progress, and can talk to other learners. This phase delivers the
Explore tab, real authentication, the Profile tab, and comments.

## 1. Authentication

Firebase Auth is already configured for **Sign in with Apple** and **email/password**.

**Guest-first.** On first launch, sign in anonymously in the background. The learner can
browse, watch, quiz, and track progress immediately with no account wall. Watching
something before being asked for an account is the point.

**Upgrade prompts** appear only at the moment of need — liking, commenting, opening the
AI tutor, or on the third completed video. Never a modal on launch.

**Sign-in sheet** offers, in this order:
1. **Sign in with Apple** — primary button, black, per Apple's HIG. Required by App
   Review since a third-party sign-in is offered, and the cleanest path.
2. **Continue with email** — expands to email + password, with sign-up / sign-in
   detection and a password reset link.

Use `linkWithCredential` to upgrade the anonymous account so all guest progress, likes,
and quiz history carry over. Handle `credentialAlreadyInUse` explicitly: the learner
already has an account, so sign into it and offer to merge — at minimum, tell them
their guest progress won't transfer rather than silently dropping it.

Apple sign-in gives a private relay email and often no name. On first sign-in, prompt
for a display name and handle in a short sheet, using `claimHandle` from Phase 1.
Default the display name to Apple's `fullName` when provided.

**Account screen** (under Profile) supports: sign out, delete account, and view linked
providers. Account deletion is required by App Review — implement a
`deleteAccount` callable that soft-deletes the user doc, anonymizes their comments
(`authorName` → "Deleted user", keep the thread), removes progress and likes, then
deletes the Auth user.

## 2. Onboarding

Three screens, skippable, shown once:

1. **What Shui is** — one sentence, one illustration: "Short videos that teach you
   something, then check you learned it."
2. **Pick your interests** — the 11 categories as a tappable grid, minimum 1, no
   maximum. Writes `users/{uid}.interests`, which drives feed ordering from Phase 2.
3. **How the quiz works** — a static mock of the quiz card explaining that the quiz is
   the point and that missed questions come back.

Store `hasCompletedOnboarding` in local preferences (the trimmed `UserProfile` from
Phase 0), not in Firestore, so it never blocks launch on a network call.

## 3. Explore tab

**Level 1 — Categories.** A grid of the 11 category tiles: SF Symbol, title,
`accentHex` tint, topic count. Tapping opens the category page. Above the grid, a
search field (see §5) and a "Continue learning" row of in-progress topics with their
mastery bars.

**Level 2 — Category page.** Header with the category title and description, then a
list of public topics: cover image, title, subtitle, video count, total duration,
learner count, and — if the learner has started it — a thin mastery bar. Sort by
`publishedAt desc` with a segmented control for "Newest" / "Most learners". Paginate.

**Level 3 — Topic page.** The most important screen in this tab.

- Cover image, title, subtitle, creator name and handle, category chip.
- Primary action: **Start learning** (or **Continue** at video *n*) which pushes the
  Phase 2 feed in topic mode at the right index.
- Progress block for the learner: mastery percent with the bar, videos completed /
  total, quiz accuracy, and next review date if any items are due.
- Full markdown description.
- Ordered list of videos: thumbnail, index, title, duration, and a state glyph —
  unwatched, watched, quiz passed, needs review. Tapping any row opens the feed at that
  video.
- Private topics are visible only to their owner and admins, with a "Private" badge.

## 4. Profile tab

Header: photo, display name, `@handle`, current streak, edit button.

Then three sections:

**Progress by subject.** One row per category the learner has any progress in:
category glyph, name, an aggregate mastery bar across that category's topics, and
"3 of 7 topics started". Expanding a row lists the individual topics with their own
bars. This is the "progress bar for each subject" requirement — aggregate at the
category level, detailed at the topic level, both computed from
`users/{uid}/topicProgress` and never recomputed on the client from raw events.

**Liked videos.** A three-column grid of thumbnails from `users/{uid}/likes`, newest
first, paginated. Tapping opens a feed containing exactly the liked videos, in that
order. Long-press to unlike.

**Activity.** Videos completed, quizzes passed, overall accuracy, longest streak, and
a "Due for review" count that opens a review-only feed. Keep this factual. No badges,
no confetti, no "you're on fire" pressure — the streak number is enough.

Settings, reachable from the profile header: account, notifications (Phase 6+ concern —
show it disabled with "coming soon" rather than a dead toggle), about, privacy policy
and terms links, and — visible only when the `role` claim is `creator` or `admin` — an
entry point to Creator mode, which Phase 5 builds.

## 5. Search

Firestore has no full-text search, so keep this honest and small: client-side prefix
matching over topic `title` and `tags`, scoped to the topics already cached plus a
`title >= q, title < q + ` range query. It finds topics, not videos.

Show clearly that search covers topics. If real search matters later, that means
Algolia or Typesense — note it as a follow-up and do not fake it now.

## 6. Comments

A sheet presented from the feed's comment button, over the paused video.

- Header: "Comments · 42".
- Sorted newest first, top-level only, each with up to 3 visible replies and a
  "View N replies" expander. One level of threading, per the Phase 1 schema.
- Each row: author photo, display name, `@handle`, relative timestamp, text, a like
  glyph with count, and a Reply button.
- Composer pinned to the bottom, with the reply target shown as a dismissible chip.
- **Requires a real account.** Guests see the composer replaced by a "Sign in to join
  the conversation" button that opens the sign-in sheet. This is the requirement that
  commenting needs Apple (or email) sign-in — enforced by Firestore rules from Phase 1,
  not only by hiding the UI.
- The author may edit within 15 minutes and delete at any time (soft delete renders as
  "Comment deleted" so replies keep their context).
- Every comment has a **Report** action opening a reason picker that writes to
  `reports`. Also offer "Block this user", stored locally and applied as a client-side
  filter — a real server-side block list is a later decision.
- Optimistic insert on post, reconciled against the server write. On failure, keep the
  draft text and show a retry.

Moderation is deliberately minimal here: report + soft delete + creator/admin delete on
their own videos. Do not build a moderation queue in this phase; the `reports`
collection accumulates and Phase 6's dashboard surfaces it.

## 7. Deep links

Register the `shui://` URL scheme and a Universal Links entitlement placeholder.
Handle `shui://video/{videoId}` and `shui://topic/{topicId}` by opening the feed or
topic page directly, signing in anonymously first if needed. Share sheets from Phase 2
should produce working links by the end of this phase.

## 8. Analytics

Log a small, deliberate event set — enough to answer "are people learning?", not a
firehose: `video_started`, `video_completed`, `quiz_submitted` (with score and pass),
`quiz_skipped`, `topic_started`, `interest_selected`, `sign_in_completed`,
`comment_posted`, `ai_opened`. Include `videoId`, `topicId`, `categoryId` where
relevant. No PII in parameters.

## 9. Verify

1. Fresh install → anonymous sign-in → watch a video → complete a quiz, all with no
   account.
2. Tapping Like as a guest opens sign-in; completing Apple sign-in links the account
   and the earlier quiz progress is still present in `users/{uid}/topicProgress`.
3. Email sign-up, sign-out, sign-in, and password reset all work.
4. A guest is denied comment creation by rules — verify by attempting a direct write in
   the emulator with an anonymous token.
5. Interests picked at onboarding visibly change feed ordering.
6. Topic page → Start learning opens the feed at the right video in topic mode; Back
   returns to the topic page with progress updated.
7. Profile mastery bars match the values in `topicProgress`, and the category-level
   aggregate equals the mean of its topics.
8. Comment post / reply / edit-within-15-minutes / delete / report all work; a deleted
   comment keeps its replies visible.
9. `shui://video/{id}` opens the right video from a cold start.
10. Account deletion removes the user and anonymizes their comments.

## Out of scope

The AI tutor (Phase 4), creator tools (Phase 5), the web dashboard (Phase 6), push
notifications, real full-text search, server-side blocking.
