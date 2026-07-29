# Phase 1 — Backend: Firestore model, rules, Functions, R2 pipeline, seed

Read `prompts/README.md` first. Phase 0 must be merged and building.

## Goal

Stand up the entire server side and the Swift repository layer that talks to it, with
nothing driven by bundled files. By the end of this phase a topic, its videos, and its
quizzes exist in Firestore, the video files live in R2, an upload can be initiated and
completed end-to-end from a test harness, and every access rule is covered by an
emulator test.

No consumer UI in this phase. The deliverable is a correct, tested backend plus a Swift
API surface the later phases consume.

## 1. Firestore data model

Firestore is denormalized on purpose: the feed must read one collection and render,
without joins. Counters and denormalized copies are maintained by Functions, never by
clients.

### `categories/{categoryId}`

Fixed taxonomy, seeded once, editable by admins only. `categoryId` is a stable slug.

```
title:        string          // "Exam Prep"
slug:         string          // "exam-prep"
description:  string          // one sentence, shown on the Explore page
sfSymbol:     string          // SF Symbol name for the tile
accentHex:    string          // "F59E0B" — tile tint
sortOrder:    number
topicCount:   number          // maintained by Function
isActive:     boolean
```

Seed exactly these, in this order:

| slug | title | description |
|---|---|---|
| `personal-development` | Personal Development | Habits, focus, discipline, and how to actually change behavior. |
| `book-summaries` | Book Summaries | The core argument of a book in the time it takes to make coffee. |
| `skills` | Skills | Concrete, practical abilities you can start using today. |
| `exam-prep` | Exam Prep | Structured preparation for real tests, one question at a time. |
| `money-finance` | Money & Finance | Personal finance, investing basics, and how money actually works. |
| `career-business` | Career & Business | Interviews, negotiation, management, and building something. |
| `language-communication` | Language & Communication | Speaking, writing, and being understood. |
| `science-tech` | Science & Technology | How the physical and digital world works, explained plainly. |
| `health-fitness` | Health & Fitness | Training, nutrition, sleep, and the evidence behind them. |
| `history-culture` | History & Culture | Events, ideas, and people worth knowing about. |
| `creativity-arts` | Creativity & Arts | Craft and technique across writing, music, design, and film. |
| `test-prep-civics` | *(do not create — civics belongs under `exam-prep`)* | |

Categories are a closed set the creator selects from. Creators create *topics*, not
categories. Only an `admin` claim can write this collection.

### `topics/{topicId}`

A topic is a course: an ordered playlist of videos under one category.

```
title:            string
subtitle:         string          // one-line hook
description:      string          // markdown, shown on the topic page
categoryId:       string          // must reference an active category
coverImageURL:    string?         // R2 URL
visibility:       "public" | "private"
createdBy:        string          // uid
createdByName:    string          // denormalized display name
createdAt:        timestamp
updatedAt:        timestamp
publishedAt:      timestamp?      // set the first time visibility becomes public
videoCount:       number          // ready + public videos only, Function-maintained
totalDurationSec: number          // Function-maintained
learnerCount:     number          // distinct users with progress, Function-maintained
tags:             string[]        // max 8, lowercase, for search
isDeleted:        boolean         // soft delete
```

### `videos/{videoId}`

Top-level, not a subcollection — the feed queries across topics.

```
topicId:          string
topicTitle:        string         // denormalized for the feed overlay
categoryId:       string          // denormalized for category feeds
title:            string
description:      string          // shown in the info sheet
order:            number          // position within the topic
r2Key:            string          // "videos/{videoId}.mp4"
playbackURL:      string          // full public R2 URL
thumbnailURL:     string?
durationSeconds:  number
aspectRatio:      number          // width / height; expect ~0.5625
sizeBytes:        number
transcript:       string?         // creator-provided or auto-generated; feeds the AI tutor
visibility:       "public" | "private"
status:           "pending" | "uploading" | "ready" | "failed"
statusMessage:    string?
createdBy:        string
createdAt:        timestamp
updatedAt:        timestamp
publishedAt:      timestamp?
hasQuiz:          boolean
likeCount:        number          // Function-maintained
commentCount:     number          // Function-maintained
viewCount:        number          // Function-maintained, batched
completionCount:  number          // finished the video, Function-maintained
isDeleted:        boolean
```

A video is only ever served to learners when `status == "ready"`, `visibility ==
"public"`, `isDeleted == false`, **and** its parent topic is public and not deleted.
Enforce the parent condition by denormalizing `topicVisibility` onto the video and
having a Function fan out topic visibility changes to its videos. Do not make clients
join.

### `videos/{videoId}/quiz/current`

One quiz document per video, versioned by overwriting with an incremented `version`.

```
version:          number
questions: [
  {
    id:                 string        // stable uuid, survives edits
    prompt:             string
    options: [ { id: string, text: string } ]   // 2–6 options
    correctOptionIds:   string[]      // 1 or more
    requiredCorrectCount: number      // usually correctOptionIds.count
    explanation:        string        // shown after answering, right or wrong
    orderIndex:         number
  }
]
passThreshold:    number             // fraction 0–1, default 0.6
updatedBy:        string
updatedAt:        timestamp
```

Validate server-side in a Function on write: 1–5 questions per video, 2–6 options per
question, at least one correct option, every `correctOptionIds` entry present in
`options`, non-empty prompts and explanations. Reject with a clear message rather than
storing a malformed quiz — a broken quiz in the feed is worse than a missing one.

### `users/{uid}`

```
displayName:      string
handle:           string           // unique, lowercase, 3–20 chars
photoURL:         string?
bio:              string?
role:             "learner" | "creator" | "admin"   // display mirror of the custom claim
authProviders:    string[]         // ["apple"], ["password"], or both
interests:        string[]         // categoryIds chosen at onboarding
createdAt:        timestamp
lastActiveAt:     timestamp
currentStreak:    number
longestStreak:    number
totalVideosCompleted: number
totalQuizzesPassed:   number
isGuest:          boolean          // true while on anonymous auth
```

`handle` uniqueness is enforced by a `handles/{handle}` document holding `{ uid }`,
written in a transaction.

### `users/{uid}/topicProgress/{topicId}`

```
topicId, topicTitle, categoryId       // denormalized for the profile screen
videosCompleted:  number
videosTotal:      number             // snapshot at last write
quizzesAttempted: number
quizzesPassed:    number
correctAnswers:   number
totalAnswers:     number
masteryPercent:   number             // 0–100, see formula below
startedAt:        timestamp
lastActivityAt:   timestamp
```

**Mastery formula** — write it once, in one place, shared by app and Functions:

```
coverage = videosCompleted / max(videosTotal, 1)
accuracy = correctAnswers / max(totalAnswers, 1)
retention = quizzesPassed / max(quizzesAttempted, 1)
masteryPercent = round(100 * (0.4*coverage + 0.35*accuracy + 0.25*retention))
```

Watching without answering can never exceed 40%. That is intentional and is the
number the profile progress bar shows.

### `users/{uid}/videoProgress/{videoId}`

The per-video review record. This is where SM-2 lives now.

```
videoId, topicId
watchedSeconds:   number
completed:        boolean
completedAt:      timestamp?
quizAttempts:     number
quizBestScore:    number            // fraction 0–1
quizPassed:       boolean
lastAnsweredAt:   timestamp?
// SM-2 review state, driven by quiz results
easeFactor:       number            // default 2.5
intervalDays:     number
repetitions:      number
dueDate:          timestamp
```

### `users/{uid}/likes/{videoId}`

`{ videoId, topicId, videoTitle, thumbnailURL, likedAt }` — denormalized so the
"Liked videos" grid is a single query with no fan-out reads.

### `videos/{videoId}/comments/{commentId}`

```
uid, authorName, authorPhotoURL, authorHandle
text:             string            // 1–1000 chars
createdAt:        timestamp
editedAt:         timestamp?
parentId:         string?           // one level of threading only
replyCount:       number            // Function-maintained on the parent
likeCount:        number
isDeleted:        boolean           // soft delete keeps thread shape
reportCount:      number
```

### `videos/{videoId}/aiThreads/{uid}` and `.../messages/{messageId}`

Thread doc: `{ uid, createdAt, lastMessageAt, messageCount, mode }`.
Message doc: `{ role: "user" | "assistant", text, createdAt, tokensIn?, tokensOut? }`.
Phase 4 fills this in; create the schema and rules now.

### `reports/{reportId}`

`{ targetType: "comment" | "video", targetPath, reporterUid, reason, note, createdAt,
status: "open" | "actioned" | "dismissed" }`. Admin-read only.

## 2. Composite indexes

Define in `firestore.indexes.json` and commit:

- `videos`: `topicVisibility == public` + `status == ready` + `isDeleted == false` + `categoryId ==` + `createdAt desc`
- `videos`: `topicId ==` + `order asc`
- `videos`: `topicVisibility` + `status` + `isDeleted` + `createdAt desc` (global feed)
- `topics`: `categoryId ==` + `visibility == public` + `isDeleted == false` + `publishedAt desc`
- `topics`: `createdBy ==` + `updatedAt desc` (creator console)
- `users/{uid}/videoProgress`: `dueDate asc` (review queue)
- `videos/{videoId}/comments`: `parentId == null` + `createdAt desc`

## 3. Security rules

Write `firestore.rules` deny-by-default, and a rules test suite covering every
invariant below. Role comes from `request.auth.token.role`, never from a Firestore doc.

Helpers: `isSignedIn()`, `isNotGuest()` (`request.auth.token.firebase.sign_in_provider != "anonymous"`), `isOwner(uid)`, `hasRole(r)`, `isCreator()` (`creator` or `admin`), `isAdmin()`.

| Path | Read | Write |
|---|---|---|
| `categories/*` | anyone | admin only |
| `topics/*` | public+not deleted → anyone; otherwise owner or admin | create: creator; update/delete: owner or admin |
| `videos/*` | ready+public+topic public+not deleted → anyone; otherwise owner or admin | **client writes denied entirely** — Functions only |
| `videos/*/quiz/*` | same visibility rule as the parent video | **client writes denied** — validated through a Function |
| `users/{uid}` | own doc, plus a public-profile subset for anyone | own doc; `role`, `currentStreak`, `longestStreak`, `totalVideosCompleted`, `totalQuizzesPassed`, `handle` are Function-only |
| `users/{uid}/**` | owner | owner, except aggregate fields listed above |
| `videos/*/comments/*` | same visibility rule as the parent video | create: signed in **and not guest**, `uid == request.auth.uid`, text 1–1000 chars, `likeCount`/`replyCount`/`reportCount` must be 0 on create; update: author, `text` and `editedAt` only, within 15 minutes of `createdAt`; delete: author or admin, and only as a soft delete |
| `videos/*/aiThreads/{uid}/**` | owner | Functions only |
| `reports/*` | admin | create: signed in and not guest |
| everything else | deny | deny |

Guests (anonymous auth) may watch, track their own progress, and like — they may not
comment. That mirrors the product requirement that commenting requires a real account.

Write a rules test for each row, including the negative case. A rule without a failing-
path test is not done.

## 4. Cloud Functions

TypeScript, 2nd gen, in `functions/`. Region `us-central1`. Every callable validates
its input with a schema (zod) and throws typed `HttpsError`s.

### Callable: `createVideoUpload`

Auth: creator role.
Input: `{ topicId, title, description?, sizeBytes, durationSeconds, aspectRatio, contentType }`.

1. Verify the caller owns `topicId` (or is admin).
2. Reject `sizeBytes > 500 MB` and any `contentType` other than `video/mp4` or `video/quicktime`.
3. Allocate `videoId`, compute `r2Key = "videos/{videoId}.mp4"`.
4. Create the `videos/{videoId}` doc with `status: "uploading"`, `visibility: "private"`,
   `order` = current max + 1, and the denormalized `topicTitle` / `categoryId` /
   `topicVisibility`.
5. Mint a **presigned S3 PUT URL** against R2 using AWS SigV4 (`@aws-sdk/client-s3` +
   `@aws-sdk/s3-request-presigner`, endpoint `https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
   region `auto`), expiry 30 minutes, `ContentType` pinned to the declared value.
6. Return `{ videoId, uploadURL, r2Key, playbackURL, expiresAt }`.

R2 credentials come from Function secrets: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_BUCKET` (`shui-videos`), `R2_PUBLIC_BASE_URL`. Set with
`firebase functions:secrets:set`. They must never reach the client.

### Callable: `finalizeVideoUpload`

Auth: owner of the video.
Input: `{ videoId, thumbnailR2Key?, transcript? }`.

`HEAD` the R2 object. If missing, set `status: "failed"` with a message and throw. If
present, record `sizeBytes` from the response, set `status: "ready"`, `playbackURL`,
`thumbnailURL`, and `updatedAt`. Recompute the parent topic's `videoCount` and
`totalDurationSec`.

### Callable: `createThumbnailUpload`

Same presign flow for `thumbs/{videoId}.jpg`, `image/jpeg`, 5 MB cap. The client
generates the still with `AVAssetImageGenerator` and uploads it directly.

### Callable: `saveQuiz`

Auth: owner of the video. Input: the quiz document. Runs the validation in §1, writes
`videos/{videoId}/quiz/current` with `version` incremented, sets `hasQuiz` on the
video. Returns the stored quiz.

### Callable: `submitQuizAttempt`

Auth: any signed-in user (guests included).
Input: `{ videoId, answers: [{ questionId, selectedOptionIds }] }`.

**Grade on the server.** The client must never be trusted with correctness, and the
correct answers must not be readable ahead of time — so strip `correctOptionIds` and
`explanation` from the quiz payload the client reads, and return them from this
callable instead. (Enforce that by keeping correct answers in a sibling doc
`videos/{videoId}/quiz/answers` that rules deny to non-owners, while
`quiz/current` holds only prompts and options.)

Then, in a transaction:
1. Grade each question, compute `score` and `passed = score >= passThreshold`.
2. Update `users/{uid}/videoProgress/{videoId}`: bump attempts, best score, `passed`.
3. Apply SM-2 using the shared scheduler logic: `passed` → grade `good`, failed →
   grade `again`. Write back `easeFactor`, `intervalDays`, `repetitions`, `dueDate`.
4. Recompute `users/{uid}/topicProgress/{topicId}` including `masteryPercent`.
5. Update the user's streak (`lastActiveAt` day boundary) and aggregate counters.

Return `{ score, passed, results: [{ questionId, wasCorrect, correctOptionIds, explanation }] }`.

Port the SM-2 math from `SpacedRepetitionScheduler.swift` verbatim into
`functions/src/lib/sm2.ts`, and port its Swift unit tests into Jest tests. The two
implementations must agree; that agreement is the thing being tested.

### Callable: `markVideoCompleted`

Input `{ videoId, watchedSeconds }`. Sets `completed` when watched ≥ 90% of duration,
increments `completionCount` and the user's counters, updates topic progress coverage.

### Callable: `toggleLike`

Input `{ videoId }`. Transactionally creates or deletes `users/{uid}/likes/{videoId}`
and adjusts `videos/{videoId}.likeCount`. Returns the new state.

### Callable: `setTopicVisibility` / `setVideoVisibility`

Auth: owner or admin. Flips `visibility`, stamps `publishedAt` on first publish, and
fans `topicVisibility` out to every child video. Refuse to publish a topic with zero
ready videos, and refuse to publish a video with no quiz — return an actionable error
message the creator console can display verbatim.

### Callable: `softDeleteTopic` / `softDeleteVideo` / `softDeleteComment`

Set `isDeleted`, fan out, adjust counters. Never hard-delete: R2 objects are cleaned
up by a scheduled job, and comment threads need their shape preserved.

### Callable: `claimHandle`

Transactionally reserves `handles/{handle}` and writes `users/{uid}.handle`.

### Callable: `assignRole`

Admin only. Sets the `role` custom claim via the Admin SDK and mirrors it to the user
doc. Also provide `scripts/bootstrap-admin.ts`, run once locally with a service
account, to grant the first `admin` claim — document it in the README.

### Triggers

- `onDocumentWritten("videos/{videoId}/comments/{commentId}")` → maintain
  `video.commentCount` and the parent comment's `replyCount`.
- `onDocumentCreated("users/{uid}")` → default role claim `learner`, default fields.
- `onSchedule("every 24 hours")` → `cleanupOrphanedUploads`: delete R2 objects whose
  video doc is `failed` or `isDeleted` and older than 7 days; mark `uploading` docs
  older than 24 hours as `failed`.
- `onSchedule("every 1 hours")` → `flushViewCounts`: drain a `viewEvents` collection
  into `videos.viewCount` in batches. Clients write view events, never counters.

## 5. Swift repository layer

Add `Sources/Data/`. Every type is a protocol + live implementation + in-memory fake.

```
CategoryRepository      list() -> [Category]
TopicRepository         topics(inCategory:), topic(id:), myTopics(), create/update, setVisibility
VideoRepository         feed(categoryId:limit:cursor:), videos(inTopic:), video(id:)
QuizRepository          quiz(forVideo:) -> Quiz            // prompts + options only
                        submit(attempt:) -> QuizResult      // via callable
ProgressRepository      topicProgress(), videoProgress(), markCompleted(), dueForReview()
SocialRepository        toggleLike(), likedVideos(), comments(forVideo:), postComment(), report()
UserRepository          currentUser(), updateProfile(), claimHandle(), interests
UploadRepository        createVideoUpload(), uploadFile(to:), finalize(), createThumbnailUpload()
AITutorRepository       (protocol only in this phase; Phase 4 implements)
```

Rules:
- Codable structs mirroring the schema, with `@DocumentID`-style id handling. Decode
  defensively: an unknown enum value or missing optional field must not crash the feed.
- All Firestore/Functions access is confined to `Sources/Data/`. `git grep "import Firebase"`
  outside that directory and `FirebaseBootstrap.swift` must return nothing.
- Paginate with cursors, never `getDocuments()` on an unbounded collection.
- One `AppEnvironment` object holding every repository, injected once at the root, so
  previews and tests can swap in fakes.

## 6. Seed the civics content as one real topic

Write `scripts/seed_civics.ts` (Admin SDK, run locally) that:

1. Creates the 11 categories above.
2. Creates one topic: **"U.S. Citizenship Civics Test (2025)"** under `exam-prep`,
   `visibility: "private"` initially, owned by the admin uid, with a description
   noting it follows USCIS form M-1778 (09/25).
3. Reads `scripts/sources/official_2025_civics.json` — the **2025 128-question** test,
   which is the current official version. Do not use the old 2008 100-question bundle;
   it was already deleted in Phase 0.
4. Groups questions into videos by category section, producing one video shell per
   section with `status: "pending"` and no `playbackURL` — you're seeding the *quizzes
   and structure*, not fake videos. The creator uploads real video against these
   shells in Phase 5.
5. Writes a quiz per video from the official questions: prompt verbatim, the official
   accepted answer as the correct option, and three distractors drawn from other
   answers in the same section. Put the official accepted-answer list into
   `explanation` so the learner sees exactly what USCIS accepts.
6. **Skips the 9 questions whose answers change over time or by state** — sitting
   President, Vice President, Speaker, Chief Justice, President's party, the learner's
   Senators, Representative, Governor, and state capital. The old app fed placeholder
   strings like *"Update in Settings > Content Admin before release"* into the quiz as
   the correct answer. Do not reintroduce that. Log the skipped questions and note in
   the topic description that time-sensitive and state-specific questions are covered
   separately. A "your officials" feature is a deliberate later decision, not a
   half-built one.
7. Is idempotent — safe to re-run, keyed on deterministic ids.

## 7. Emulator and CI

Add `firebase.json` configuring the Firestore, Auth, and Functions emulators. Add npm
scripts: `emulate`, `test:rules`, `test:functions`, `seed:local`. Document in the README
how to point the iOS app at the emulator with a debug-only launch flag.

## 8. Verify

1. Rules suite passes, including a negative test per row of the table in §3.
2. Functions unit tests pass, including SM-2 parity with the Swift implementation.
3. Seed script runs twice with no duplicates.
4. A temporary debug screen (delete before merging, or hide behind `#if DEBUG`) can:
   pick a local file → `createVideoUpload` → PUT to R2 → `finalizeVideoUpload` → the
   video appears with `status: "ready"` and plays from its `playbackURL` in `AVPlayer`.
5. `submitQuizAttempt` grades correctly, and `quiz/current` read as a non-owner
   contains **no** correct answers.
6. A guest (anonymous) account can watch and like but is denied comment creation by
   rules, not by UI.
7. `git grep "import Firebase"` outside `Sources/Data/` returns nothing.
8. No R2 key, model key, or service-account file anywhere in the repo or its history
   added by this phase.

## Out of scope

No consumer screens, no creator UI, no AI implementation. If a decision here is only
needed by a later phase's UI, defer it.
