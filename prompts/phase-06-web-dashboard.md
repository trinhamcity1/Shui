# Phase 6 — Web dashboard: bulk authoring on a laptop

Read `prompts/README.md` first. Phases 1 and 5 must be merged. The dashboard is a
second client over the same Firebase backend — it adds **no** new data model and **no**
new privileged path.

## Goal

Do on a laptop what the phone can't do comfortably: write long descriptions, build
quizzes with a real keyboard, upload a batch of videos, review the reports queue, and
see how content is actually performing. Same content, same rules, bigger screen.

## 1. Non-negotiable constraint

Every write goes through the **same Cloud Functions and the same Firestore security
rules** as the iOS app. No Admin SDK in the browser, no service account in the frontend,
no "web-only" endpoint that skips validation. If the dashboard needs something the
callables don't offer, extend the callable so both clients get it.

If you find yourself writing a second copy of the quiz validation logic, stop — move it
into a shared module the Function imports, and have the dashboard call the Function.

## 2. Stack

- **Vite + React + TypeScript**, in `web/` at the repo root.
- **Firebase JS SDK** v10+: Auth, Firestore, Functions. Reuse `shui-prod`; register a
  new Web app in the Firebase console and put its config in `web/.env` (gitignored,
  with a committed `.env.example`).
- **Tailwind** for styling. Mirror the app's `Theme.shell` tokens — same warm off-white
  canvas, same gradient accent, same rounded geometry — so the two surfaces feel like
  one product. Extract the hex values from `Theme.swift` into
  `web/src/theme.ts` with a comment pointing back at the Swift source.
- **TanStack Query** for server state, **react-hook-form + zod** for forms, reusing the
  same zod schemas the Functions use via a shared `packages/schemas` workspace if that's
  cheap to set up; duplicate them with a pointer comment if it isn't.
- Deploy to **Firebase Hosting** at a `creators.` subdomain or `/admin` path. Add a
  GitHub Action that builds and deploys on push to main.

Keep dependencies boring and few. This is an internal tool that must still work in two
years.

## 3. Auth and gating

- Sign in with Google, Apple, or email/password via Firebase Auth.
- On load, read the `role` custom claim. `learner` (or no claim) sees a plain "You don't
  have creator access" page and a sign-out button — not a redirect loop, not a blank
  screen.
- `creator` sees their own content. `admin` sees everything plus the admin sections.
- Handle claim staleness: force `getIdToken(true)` on login and expose a "Refresh
  permissions" action, since a freshly granted role otherwise takes an hour to appear.

## 4. Screens

### Topics list
Table with search, category filter, and status filter (draft / private / public). Columns:
title, category, videos, duration, learners, avg quiz score, visibility, updated. Row
click opens the editor. Bulk select for publish / unpublish / delete.

### Topic editor
Two-pane: metadata form on the left, ordered video list on the right.
- Markdown description with live preview — this is the main reason to author on a laptop.
- Cover image drag-and-drop with 3:2 crop.
- Drag-to-reorder videos, batching `order` writes.
- Inline publish checklist mirroring the Phase 1 publish gate, so blockers are visible
  before the button is pressed.

### Video upload — batch
The dashboard's biggest advantage over the phone.
- Drop a folder of files. For each: `createVideoUpload` → presigned `PUT` to R2 → 
  `finalizeVideoUpload`, with a concurrency limit of 3 and per-file progress.
- Read duration and dimensions client-side from a hidden `<video>` element; generate a
  thumbnail by seeking and drawing to a `<canvas>`.
- Derive a default title from the filename, editable inline in the queue.
- Browsers can't transcode reliably, so validate instead: reject files over 500 MB or
  non-H.264, with a clear message telling the creator to export smaller. Do not attempt
  ffmpeg-in-wasm in this phase.
- The queue survives a page reload (persist state to `localStorage`, resume or clearly
  fail each item).

### Video editor
Metadata, visibility, replace file, soft delete. A transcript editor with the auto-
generated text loaded for correction — a corrected transcript directly improves the
Phase 4 tutor, so make this pleasant: monospace, generous width, autosave draft.

### Quiz builder
The same rules as Phase 5, keyboard-first:
- Add / reorder / delete questions and options without reaching for the mouse.
- Tab order that actually flows: prompt → options → correct toggles → explanation → next
  question.
- A live preview panel rendering the quiz roughly as the phone shows it.
- Keyboard shortcuts: `⌘↵` save, `⌘⇧N` new question.
- CSV import for question banks: `prompt,optionA,optionB,optionC,optionD,correct,explanation`.
  Validate every row, show a per-row error report, and import nothing until the whole file
  is valid. This is how a 128-question exam-prep topic gets authored in an afternoon.

### Analytics
Per topic and per video: views, completion rate, quiz attempt rate, average score, and
the **per-question miss rate**. That last one is the most useful number in the whole
dashboard — a question everyone misses is usually a badly written question or a badly
explained video, and you can only see it here. Read from the counters Phase 1 maintains;
add a `quizQuestionStats` aggregation Function if per-question data isn't already being
recorded, and note that as a Phase 1 amendment.

### Admin: reports, roles, categories
Same capabilities as Phase 5's admin surface, laid out for real work: a reports queue
with the content in context and keyboard-driven dismiss/action, role search and
grant/revoke with confirmation, and category management with drag ordering.

## 5. Quality bar

- **Responsive enough** for a 13" laptop and a large monitor. Not mobile-optimized — the
  phone has its own creator mode.
- **Optimistic updates** with rollback and the server's error message on failure.
- **Never lose typed input.** Autosave drafts to `localStorage` for every long-form field.
  A closed tab must not cost an hour of quiz writing.
- **Loading and empty states** for every list. No layout shift on load.
- **Accessible**: real form labels, visible focus rings, keyboard-operable everywhere,
  no div-as-button.
- **Error boundary** at the route level so one broken row doesn't blank the app.

## 6. Verify

1. A `learner` account signing in sees the no-access page and nothing else.
2. A `creator` sees only their own topics; direct-navigating to another creator's topic id
   is denied by rules, not just hidden.
3. Batch-upload 5 files: all reach `status: "ready"` in R2 and Firestore, with correct
   durations and generated thumbnails.
4. CSV import of 20 questions: one deliberately malformed row blocks the entire import
   with a precise row-and-column error.
5. Editing a topic in the dashboard is visible in the iOS app on next refresh, and
   vice-versa.
6. Publish gates behave identically in both clients — same rejection, same message.
7. Correcting a transcript in the dashboard measurably improves the Phase 4 tutor's
   grounding on that video (spot-check by asking a question only the corrected transcript
   answers).
8. Reload the page mid-upload queue: state resumes or fails visibly, never silently.
9. `git grep` finds no service-account key or Admin SDK import under `web/`.
10. Lighthouse accessibility score above 90 on the topic editor and quiz builder.

## Out of scope

A public marketing site, learner-facing web playback, multi-creator collaboration,
scheduled publishing, monetization, video editing in the browser.

---

## After Phase 6 — the honest remaining list

Keep this current in the main README rather than letting it drift the way the original
one did:

- **Push notifications** for review reminders — the natural fit for spaced repetition,
  and deliberately absent through Phase 6. Needs APNs, a scheduled Function reading
  `dueDate`, and a genuine restraint policy so it doesn't become nagging.
- **Voice mode for the tutor** — speaking answers aloud is a much better retention check
  than typing them, and pairs naturally with an audio-first lesson format.
- **Real full-text search** (Algolia or Typesense) once the topic count outgrows prefix
  matching.
- **Time-sensitive and state-specific civics questions** — the 9 questions Phase 1's seed
  deliberately skips. They need a "your officials" profile step and a maintained data
  source, which is a real product decision, not a data-entry task.
- **Localization**, if and when the audience justifies it. The original app carried a
  half-finished bilingual layer; if this returns, it should be a full content-translation
  pipeline in the creator tools, not paired string fields on every model.
- **StoreKit** if any of this becomes paid. The original code simulated a Free/Pro tier;
  nothing in Phases 0–6 assumes one exists.
- **Server-side user blocking** and a real moderation policy, once there is enough
  community activity to need it.
