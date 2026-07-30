import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ClaimHandleInputSchema } from "../schemas/callableInputs";

export const claimHandle = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(ClaimHandleInputSchema, request.data);

  const handleRef = db.collection("handles").doc(input.handle);
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (t) => {
    const [handleSnap, userSnap] = await Promise.all([t.get(handleRef), t.get(userRef)]);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User profile not found.");
    }
    if (handleSnap.exists && handleSnap.data()!.uid !== uid) {
      throw new HttpsError("already-exists", "That handle is taken.");
    }

    const previousHandle: string | undefined = userSnap.data()!.handle;
    if (previousHandle && previousHandle !== input.handle) {
      t.delete(db.collection("handles").doc(previousHandle));
    }

    t.set(handleRef, { uid });
    t.update(userRef, { handle: input.handle });
  });

  return { handle: input.handle };
});
