import { onCall } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { CreateApiKeyInputSchema } from "../schemas/callableInputs";
import { createApiKeyForUser } from "../lib/apiKeys";

/**
 * Self-serve, no tier gate (phase-07 §8) — `rawKey` is returned exactly once
 * in this response and never recoverable afterward, since only its hash is
 * persisted.
 */
export const createApiKey = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(CreateApiKeyInputSchema, request.data);
  const { keyId, rawKey } = await createApiKeyForUser(uid, input.label);
  return { keyId, rawKey };
});
