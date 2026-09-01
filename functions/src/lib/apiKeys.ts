import { randomBytes, createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { db } from "./admin";

/**
 * Developer-API credentials (phase-07 §8). The raw key is shown exactly once,
 * at creation — only its SHA-256 hash is ever persisted, so a leaked
 * database export can't be turned back into working credentials.
 */
export interface ApiKeyDoc {
  uid: string;
  keyHash: string;
  label: string;
  createdAt: FirebaseFirestore.Timestamp | null;
  lastUsedAt: FirebaseFirestore.Timestamp | null;
  revoked: boolean;
  requestCount: number;
  rateLimitWindowStartMs: number | null;
  rateLimitCountInWindow: number;
}

export interface ApiKeySafeProjection {
  keyId: string;
  label: string;
  createdAt: FirebaseFirestore.Timestamp | null;
  lastUsedAt: FirebaseFirestore.Timestamp | null;
  revoked: boolean;
  requestCount: number;
}

function apiKeysCollection() {
  return db.collection("apiKeys");
}

/** `shui_live_` + 32 bytes of URL-safe randomness — never guessable, never reused. */
export function generateRawApiKey(): string {
  return `shui_live_${randomBytes(32).toString("base64url")}`;
}

export function hashApiKey(rawKey: string): string {
  return createHash("sha256").update(rawKey).digest("hex");
}

export async function createApiKeyForUser(uid: string, label: string): Promise<{ keyId: string; rawKey: string }> {
  const rawKey = generateRawApiKey();
  const ref = apiKeysCollection().doc();
  await ref.set({
    uid,
    keyHash: hashApiKey(rawKey),
    label,
    createdAt: FieldValue.serverTimestamp(),
    lastUsedAt: null,
    revoked: false,
    requestCount: 0,
    rateLimitWindowStartMs: null,
    rateLimitCountInWindow: 0,
  });
  return { keyId: ref.id, rawKey };
}

/**
 * No `orderBy` on purpose — an equality filter on `uid` combined with an
 * `orderBy` on a different field (`createdAt`) would need a composite index
 * for a collection that's typically a handful of docs per user, so this
 * sorts the (small) result in memory instead.
 */
export async function listApiKeysForUser(uid: string): Promise<ApiKeySafeProjection[]> {
  const snap = await apiKeysCollection().where("uid", "==", uid).get();
  return snap.docs
    .map((doc) => {
      const data = doc.data() as ApiKeyDoc;
      return {
        keyId: doc.id,
        label: data.label,
        createdAt: data.createdAt ?? null,
        lastUsedAt: data.lastUsedAt ?? null,
        revoked: Boolean(data.revoked),
        requestCount: data.requestCount ?? 0,
      };
    })
    .sort((a, b) => (b.createdAt?.toMillis() ?? 0) - (a.createdAt?.toMillis() ?? 0));
}

export async function revokeApiKeyForUser(uid: string, keyId: string): Promise<void> {
  const ref = apiKeysCollection().doc(keyId);
  const snap = await ref.get();
  if (!snap.exists || (snap.data() as ApiKeyDoc).uid !== uid) {
    throw new HttpsError("not-found", "API key not found.");
  }
  await ref.set({ revoked: true }, { merge: true });
}

/** Read-only lookup for the `lessonsApi` request handler — never touches usage/rate-limit bookkeeping. */
export async function resolveApiKey(rawKey: string): Promise<{ uid: string; keyId: string } | null> {
  const snap = await apiKeysCollection().where("keyHash", "==", hashApiKey(rawKey)).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0]!;
  const data = doc.data() as ApiKeyDoc;
  if (data.revoked) return null;
  return { uid: data.uid, keyId: doc.id };
}

export const API_KEY_RATE_LIMIT_PER_HOUR = 20;
export const API_KEY_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

export interface RateLimitWindow {
  windowStartMs: number;
  count: number;
}

/**
 * Pure fixed-window rate limiter — a coarser circuit breaker than the AI
 * tutor's own limits (phase-07 §8), sized to catch a compromised key being
 * hammered far faster than any real developer's usage, not to police normal
 * traffic. `current: null` covers both a brand-new key and an expired
 * window; either way the caller gets a fresh window starting now.
 */
export function nextRateLimitWindow(
  current: RateLimitWindow | null,
  nowMs: number,
  windowMs: number = API_KEY_RATE_LIMIT_WINDOW_MS,
  limit: number = API_KEY_RATE_LIMIT_PER_HOUR
): { allowed: boolean; window: RateLimitWindow } {
  if (!current || nowMs - current.windowStartMs >= windowMs) {
    return { allowed: true, window: { windowStartMs: nowMs, count: 1 } };
  }
  if (current.count >= limit) {
    return { allowed: false, window: current };
  }
  return { allowed: true, window: { windowStartMs: current.windowStartMs, count: current.count + 1 } };
}

/**
 * The Firestore-backed wrapper `lessonsApi` actually calls. Always records
 * `lastUsedAt`/`requestCount` for a resolved key, even on a rate-limited
 * request — a 429 is still a real, observable use of the credential.
 */
export async function checkAndConsumeRateLimit(keyId: string): Promise<{ allowed: boolean; retryAfterSeconds?: number }> {
  const ref = apiKeysCollection().doc(keyId);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return { allowed: false };
    const data = snap.data() as ApiKeyDoc;
    const now = Date.now();
    const current: RateLimitWindow | null =
      data.rateLimitWindowStartMs != null ? { windowStartMs: data.rateLimitWindowStartMs, count: data.rateLimitCountInWindow ?? 0 } : null;
    const result = nextRateLimitWindow(current, now);

    t.set(
      ref,
      {
        rateLimitWindowStartMs: result.window.windowStartMs,
        rateLimitCountInWindow: result.window.count,
        lastUsedAt: FieldValue.serverTimestamp(),
        requestCount: FieldValue.increment(1),
      },
      { merge: true }
    );

    if (!result.allowed) {
      const retryAfterSeconds = Math.max(0, Math.ceil((result.window.windowStartMs + API_KEY_RATE_LIMIT_WINDOW_MS - now) / 1000));
      return { allowed: false, retryAfterSeconds };
    }
    return { allowed: true };
  });
}
