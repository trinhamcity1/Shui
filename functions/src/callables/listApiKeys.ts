import { onCall } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { listApiKeysForUser } from "../lib/apiKeys";

/**
 * The safe projection only — `keyHash` never leaves lib/apiKeys.ts.
 *
 * Timestamps are converted to ISO 8601 strings here, at the callable
 * boundary, rather than handing back raw Firestore `Timestamp` objects —
 * those serialize to Firestore's own `{_seconds, _nanoseconds}` shape over
 * the wire, not something a client's `Date`/`ISO8601DateFormatter` can
 * parse. Same convention `aiTutorMessage`'s rate-limit error already uses
 * for `resetAt`.
 */
export const listApiKeys = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const keys = await listApiKeysForUser(uid);
  return {
    keys: keys.map((key) => ({
      keyId: key.keyId,
      label: key.label,
      createdAt: key.createdAt?.toDate().toISOString() ?? null,
      lastUsedAt: key.lastUsedAt?.toDate().toISOString() ?? null,
      revoked: key.revoked,
      requestCount: key.requestCount,
    })),
  };
});
