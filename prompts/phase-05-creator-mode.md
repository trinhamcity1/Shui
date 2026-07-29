# Phase 5 — Creator mode: author everything from the app

Read `prompts/README.md` first. Phases 0–3 must be merged and building (Phase 4 is
independent of this one and can land in either order).

## Goal

Make the app self-sufficient. After this phase, adding a topic, uploading a video,
writing its quiz, and publishing it all happen **inside the app on a phone** — no code
change, no script, no redeploy. Content stops being a build artifact.

This is the phase that determines whether Shui can scale as a product or stays a demo.

## 1. Access

Creator mode appears only when the `role` custom claim from Phase 1 is `creator` or
`admin`. Nothing about it is visible to learners — no greyed-out tab, no locked entry.
Read the claim from the ID token on launch and refresh it on foreground so a
just-granted role appears without a reinstall.

Entry point: Settings → **Creator**, which pushes a dedicated navigation stack. Do not
add a fourth tab; this is a mode, not a peer of Learn.

`admin` additionally sees: all creators' topics, the `reports` queue, and role
management (grant/revoke `creator`). A creator sees only their own content.

## 2. Creator home

A dashboard, not a menu:

- **Draft / private topics** needing work, with what's missing ("2 videos have no quiz",
  "no cover image").
- **Published topics** with learner count, total views, and average quiz score.
- Primary action: **New topic**.
- Secondary: **Upload video** (picks a destination topic in the flow).

Numbers here come from denormalized counters, not client aggregation.

## 3. Topic editor

Create and edit in one form:

| Field | Rules |
|---|---|
| Title | required, 3–80 chars |
| Subtitle | required, ≤ 120 chars |
| Description | markdown, ≤ 4000 chars, live preview toggle |
| Category | required, picker over the 11 seeded categories — creators select, never create categories |
| Cover image | optional, picked from library or camera, cropped to 3:2, uploaded to R2 via `createThumbnailUpload`-style presign |
| Tags | up to 8, lowercase, comma entry with chips |
| Visibility | Private / Public, with the publish gate below |

Below the form, the **ordered video list**: drag to reorder (writes each video's `order`
in a batch), swipe for actions, and a per-row status badge (Uploading, Processing,
Needs quiz, Ready, Private).

Topic actions: Publish / Unpublish, Duplicate (structure only, no videos), Delete (soft,
with a typed-title confirmation because it hides every video inside).

**Publish gate.** `setTopicVisibility` refuses to publish a topic with zero ready videos.
Surface the Function's error message verbatim, and show the checklist inline before the
learner ever taps publish, so it's never a surprise.

## 4. Video upload

The flow that has to feel effortless, because it's the one you'll run hundreds of times.

1. **Pick** — `PhotosPicker` for videos, or record in-app. Accept `.mp4` and `.mov`.
2. **Inspect locally** — read duration, natural size, and file size from `AVAsset`.
   Warn (don't block) if the aspect ratio isn't roughly 9:16 or the duration is over
   10 minutes; the feed is built for vertical and short.
3. **Trim** — a simple `AVAssetTrimming`-style range selector. Optional but strongly
   preferred: it's the difference between usable and not on a phone.
4. **Transcode** — export through `AVAssetExportSession` to H.264/AAC, 1080×1920 max,
   ~4–6 Mbps. Uploading a 200 MB ProRes file over cellular is not acceptable, and R2
   egress isn't free. Show the compressed size before upload.
5. **Thumbnail** — auto-generate a still at 1s via `AVAssetImageGenerator`, let the
   creator scrub to pick a different frame, then upload it with the video.
6. **Metadata** — title (required), description, destination topic (prefilled if entered
   from a topic), position in the topic, and an optional transcript field with a note
   that leaving it blank triggers auto-transcription and that a good transcript makes the
   AI tutor markedly better.
7. **Upload** — `createVideoUpload` → direct `PUT` to the presigned R2 URL via
   `URLSession` **background** upload task → `finalizeVideoUpload`. Show real byte
   progress. Survive app backgrounding; resume or clearly fail on relaunch. Cancel must
   delete the pending video doc.
8. **Confirm** — land on the video editor with a "Add quiz" call to action, because a
   video without a quiz can't be published.

Handle the failure paths explicitly: presign expiry (re-mint and retry), network drop
(retry with backoff, then a resumable retry button), R2 4xx/5xx (mark `failed` with the
message), and app kill mid-upload (the Phase 1 cleanup job marks it failed after 24h;
the UI must show it as failed and offer re-upload).

## 5. Quiz builder

Per video, editing `videos/{videoId}/quiz/current` through `saveQuiz`.

- 1–5 questions, reorderable.
- Per question: prompt (required), 2–6 options, mark one or more correct, required
  correct count (auto-set to the number marked, overridable), and an **explanation
  (required)**. Make explanation required in the UI even though the schema tolerates
  short ones — the explanation is where learning happens and skipping it is the easiest
  way to make the app worse.
- Inline validation matching the server rules from Phase 1 exactly, so a save never
  fails for a reason the UI could have caught.
- **Preview** — render the actual Phase 2 quiz card with this quiz over a still from the
  video. Authoring blind is how bad quizzes ship.
- Optional accelerator, and clearly labelled as a draft-generator: **Suggest questions**
  calls a Cloud Function that drafts 3 questions with options and explanations from the
  video transcript. The creator must review and edit before saving; never auto-save
  generated questions, and mark them `source: "ai-draft"` until edited so you can audit
  quality later.

Per-video actions: Edit metadata, Replace video file (new upload against the same
`videoId`, invalidating the old R2 object), Public / Private, Delete (soft).

## 6. Admin surface

Only for `admin`:

- **All topics** across creators, with a creator filter.
- **Reports queue** from `reports`: the reported comment or video in context, with
  Dismiss, Delete content, and (for repeat offenders) a note field. Writes `status` and
  an `actionedBy`/`actionedAt` audit trail.
- **Roles**: search a user by handle or email, grant or revoke `creator`, via the
  `assignRole` callable. Show a confirmation naming the user — this grants publishing
  rights to everyone in the app.
- **Category management**: edit titles, descriptions, symbols, sort order, and
  `isActive`. Creating a new category is allowed here and nowhere else.

## 7. Cross-cutting requirements

- **Offline drafts.** Topic and quiz edits are drafted locally and saved to the server on
  demand or when connectivity returns. Losing a quiz you typed on the subway is
  unacceptable. Uploads are the exception — they require connectivity and say so.
- **Optimistic but honest.** Show local state immediately; on server rejection, revert
  and show the server's message.
- **No destructive action without confirmation**, and no hard deletes anywhere.
- **Audit fields** on every write: `updatedBy`, `updatedAt`.
- **Keyboard handling**: long-form text fields must not sit under the keyboard, and every
  form is dismissible without losing input.
- **Accessibility and Dynamic Type** apply to creator screens too. You will use these
  more than anyone.

## 8. Retire the seeding script's role

Once creator mode works, `scripts/seed_civics.ts` exists only to bootstrap a fresh
environment. Update the README: content is authored in the app; the seed script is for
initial setup and local emulator work only. Do not add new content to it.

## 9. Verify

End-to-end, on a physical device, signed in as a creator, with no code changes:

1. Create a topic under **Skills**, private.
2. Record or pick a 45-second vertical video, trim it, pick a thumbnail frame, upload it.
   Confirm the R2 object exists and `status` becomes `ready`.
3. Write a 3-question quiz with explanations; preview it; save it.
4. Attempt to publish the topic before the quiz exists → blocked with a clear message.
   After the quiz → publishes.
5. Sign in as a separate learner account on another device or simulator: the topic appears
   in Explore under Skills, the video appears in the feed, the quiz grades correctly, and
   `topicProgress` updates.
6. Set the video to private → it disappears from the learner's feed within one refresh.
7. Reorder three videos by drag; the learner's topic page reflects the new order.
8. Kill the app mid-upload; relaunch; the video shows as failed or resumes, never as a
   silent ghost row.
9. Edit a quiz question while offline; go online; the edit persists.
10. As admin: grant `creator` to a second account and confirm Creator mode appears there
    after a foreground refresh, with no reinstall.

## Out of scope

The web dashboard (Phase 6), scheduled publishing, multi-creator collaboration on one
topic, monetization, video captions/subtitles rendering, analytics beyond the counters
already maintained.
