import { onCall } from "firebase-functions/v2/https";
import { auth, db } from "../lib/admin";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { AssignRoleInputSchema } from "../schemas/callableInputs";

export const assignRole = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const input = parseInput(AssignRoleInputSchema, request.data);

  const userRecord = await auth.getUser(input.uid);
  const existingClaims = userRecord.customClaims ?? {};
  await auth.setCustomUserClaims(input.uid, { ...existingClaims, role: input.role });
  await db.collection("users").doc(input.uid).update({ role: input.role });

  return { uid: input.uid, role: input.role };
});
