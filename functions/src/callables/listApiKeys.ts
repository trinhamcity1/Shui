import { onCall } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { listApiKeysForUser } from "../lib/apiKeys";

/** The safe projection only — `keyHash` never leaves lib/apiKeys.ts. */
export const listApiKeys = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const keys = await listApiKeysForUser(uid);
  return { keys };
});
