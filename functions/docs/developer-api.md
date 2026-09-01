# Shui Lessons API — v1

Generate a Shui video lesson from your own code, against your own Shui account's
credit balance and current tier. Self-serve: any account (Free through Pyramidion)
can mint a key. **Pyramidion** ($200/mo) is sold with API access as its named perk —
one shared credit wallet between the app UI and this API — but it isn't a hard gate;
Siltstone remains the natural low-friction way to try the API before committing to a
subscription. See `prompts/phase-07-lessons-on-demand.md` §8 for the product spec this
implements; if the two ever disagree, this file describes the real code
(`functions/src/api/lessonsApi.ts`) and should be corrected to match it, not the other
way around.

Output from this API never appears in the Shui iOS app's Social tab or any other
user's view — it's an isolated developer integration surface. It **does** share
Shui's cross-account lesson cache, so a topic someone has already generated
(by anyone, through the app or the API) may come back instantly at no cost to you.

## Getting a key

Mint a key from **Settings → Developer API** in the Shui app (`createApiKey`
callable). The raw key (`shui_live_...`) is shown exactly once — Shui only ever
stores its SHA-256 hash, so if you lose it, revoke it (`revokeApiKey`) and mint a
new one. `listApiKeys` (in-app) shows label, creation date, last-used time, and
request count for your keys — never the key itself.

## Base URL

```
https://us-central1-<your-firebase-project-id>.cloudfunctions.net/lessonsApi
```

## Authentication

Every request needs an `x-api-key` header carrying the raw key. There is no
Firebase Auth token on this path — the key alone resolves to your account.

```
x-api-key: shui_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

A missing, invalid, or revoked key gets `401 unauthorized`.

## Pricing

Flat **$4.00/minute** of finished lesson, debited from your credit balance *before*
generation starts — the same rate and the same pre-debit-then-refund-on-failure
mechanics the app uses (see phase-07 §4/§7). Your account's current tier decides the
lesson length (`timing`) every generation uses: Free/Siltstone/Obsidian render 0.5–1
minute lessons, Alabaster/Pyramidion render 2-minute lessons — this isn't a
per-request choice. Insufficient balance returns `402 resource_exhausted`.

## Endpoints

### `POST /v1/lessons`

Start generating a lesson.

**Request body**

```json
{ "topic": "the causes of the French Revolution" }
```

`topic`: 1–300 characters, required.

**Response — `202 Accepted`**

```json
{ "id": "a1b2c3d4-...", "status": "generating" }
```

`status` is `"ready"` immediately when the topic hits Shui's shared lesson cache
(§5) — poll anyway; treat both the same way.

**Errors**

| HTTP | `error.code` | Cause |
|---|---|---|
| 400 | `invalid_argument` | Missing/oversized `topic`, or Claude refused the topic as off-policy |
| 402 | `resource_exhausted` | Insufficient credit balance |
| 401 | `unauthorized` | Missing/invalid/revoked key |
| 429 | `rate_limited` | Rate limit exceeded (see below) |

### `GET /v1/lessons/{id}`

Poll a lesson's status. `id` is the value returned by `POST /v1/lessons`.

**Response — `200 OK`, still generating**

```json
{ "id": "a1b2c3d4-...", "status": "generating" }
```

**Response — `200 OK`, ready**

```json
{
  "id": "a1b2c3d4-...",
  "status": "ready",
  "videoUrl": "https://.../a1b2c3d4.mp4",
  "durationSeconds": 118
}
```

`videoUrl` points at the watermarked copy or the clean master depending on *your
account's tier at the moment you call this endpoint* — Free/Siltstone/Obsidian get
the watermarked copy, Alabaster/Pyramidion get the clean master, regardless of which
tier you were on when generation started.

**Response — `200 OK`, failed**

```json
{ "id": "a1b2c3d4-...", "status": "failed", "message": "GolpoAI render error: ..." }
```

A failure automatically refunds the debited credit to your balance.

**Errors**

| HTTP | `error.code` | Cause |
|---|---|---|
| 404 | `not-found` | No lesson with that id |
| 403 | `permission-denied` | That lesson belongs to a different account |

## Rate limits

20 requests/hour per key, a circuit breaker against a compromised or misbehaving
key rather than a limit on normal usage — one real integration polling a handful of
in-flight lessons stays well under it. Exceeding it returns `429 rate_limited` with
a `Retry-After` header (seconds).

## Content moderation

The same refusal check the app's Create flow relies on runs on every topic here too
— there's no app UI in front of this surface to catch an obviously bad topic
otherwise. A refused topic returns `400 invalid_argument` and is never charged
(the pre-debit is reversed).

## Errors — general shape

Every error response is:

```json
{ "error": { "code": "invalid_argument", "message": "human-readable detail" } }
```
