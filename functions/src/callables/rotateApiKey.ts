import { onCall } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { RevokeApiKeyInputSchema } from "../schemas/callableInputs";
import { rotateApiKeyForUser } from "../lib/apiKeys";

/** Same `{ keyId }` shape as revokeApiKey — rotate just replaces the secret instead of disabling it. */
export const rotateApiKey = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(RevokeApiKeyInputSchema, request.data);
  const { rawKey } = await rotateApiKeyForUser(uid, input.keyId);
  return { rawKey };
});
