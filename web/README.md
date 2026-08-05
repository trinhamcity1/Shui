# Shui Creator Dashboard

The browser half of Phase 6 (`prompts/phase-06-web-dashboard.md`) — bulk authoring on a
laptop, against the exact same Firebase backend the iOS app uses. No new data model, no
new privileged path: every write goes through the same Cloud Functions and Firestore
rules as the phone.

## Stack

Vite + React 19 + TypeScript, Tailwind CSS v4, Firebase JS SDK v12, TanStack Query,
react-hook-form + zod, react-router-dom. See `prompts/phase-06-web-dashboard.md` §2 for
why each one.

## One-time setup (manual — nothing in this repo can do these for you)

1. **Register a Web app for `shui-prod`.** Firebase console → Project settings →
   General → Your apps → Add app → Web. This produces a config object (API key, auth
   domain, etc.) — it's a public client config, not a secret, same status as
   `GoogleService-Info.plist` for the iOS app.
2. **Copy `.env.example` to `.env`** and fill in the six `VITE_FIREBASE_*` values from
   that config. `.env` is gitignored (root `.gitignore`'s `*.env` rule) so this never
   gets committed.
3. `npm install`, then `npm run dev` for a local server, or `npm run build` for a
   production bundle in `dist/`.

Deploying to Firebase Hosting and the CI pipeline that does it on push are Phase 6.10
work, not part of this scaffold — see `PROGRESS.md`'s Phase 6 section for current status.

## Decisions worth knowing about

- **`zod` is pinned to `^3.23.8`, matching `functions/`'s version exactly** — not the
  newer zod v4 that's otherwise current. The spec's own guidance is to reuse the
  Functions' zod schemas via a shared workspace "if that's cheap to set up," and
  duplicate them with a pointer comment if it isn't. This repo has no existing npm
  workspace tooling (`functions/` is a standalone package), and standing one up now
  would mean restructuring `functions/package.json` too — more invasive than this
  scaffold needs to be. Duplicating is the chosen path (schemas land in a later
  sub-phase), and staying on the same zod major as the backend avoids the two clients
  validating the same shape slightly differently.
- **`typescript` is pinned to `^6.0.3`, not the newer TypeScript 7** — confirmed via a
  real `npm install` that `typescript-eslint`'s current release only supports
  TypeScript `<6.1.0`; 7.x fails dependency resolution outright. Worth revisiting once
  `typescript-eslint` catches up.
- **Two `npm audit` findings on `react-router` are left unaddressed on purpose.** Both
  are scoped to React Router's RSC ("framework") mode — server actions, the
  `__manifest` endpoint, SSR hydration — none of which this app uses; it's a plain
  client-rendered SPA on `BrowserRouter`. Downgrading to the version `npm audit fix`
  suggests was tried and rejected: it reintroduces nine *other* disclosed
  vulnerabilities (open redirects, XSS, DoS) that were fixed in later releases, a worse
  trade for a fix that doesn't apply to how this app actually uses the library. Worth a
  fresh look next time dependencies are updated, not something to keep re-deciding by
  hand indefinitely.
- **Tailwind's color tokens are duplicated between `src/theme.ts` and `src/index.css`'s
  `@theme` block**, both by hand from `Shui/Sources/Theme/ThemePalettes.swift` and
  `Theme.swift`. Tailwind v4's `@theme` is plain CSS, evaluated at build time — it can't
  import a `.ts` module, so there's no way to generate one from the other. If a color
  changes on the Swift side, both files need the same manual update; `theme.ts` is
  there for any future JS-side color logic beyond what Tailwind utility classes cover
  (nothing needs that yet).
- **Dark mode isn't wired up** — only `LightPalette`'s values are in `index.css`
  (`darkPalette` is exported from `theme.ts` for later, unused today). The dashboard has
  no theme toggle yet; this is a laptop tool, not the phone app, and wasn't asked for.
