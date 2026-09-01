import { onCall } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { RevokeApiKeyInputSchema } from "../schemas/callableInputs";
import { revokeApiKeyForUser } from "../lib/apiKeys";

export const revokeApiKey = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(RevokeApiKeyInputSchema, request.data);
  await revokeApiKeyForUser(uid, input.keyId);
  return { revoked: true };
});
