import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { auth } from "../lib/admin";

/**
 * Firestore rules require users/{uid} to be created with role: "learner"
 * already in the document (a display mirror), but the custom claim that
 * rules actually trust (request.auth.token.role) can only be set here, via
 * the Admin SDK, once the account exists.
 */
export const onUserCreated = onDocumentCreated("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const userRecord = await auth.getUser(uid);
  if (userRecord.customClaims?.role) {
    return; // e.g. assignRole already ran before the profile doc was created
  }
  await auth.setCustomUserClaims(uid, { ...userRecord.customClaims, role: "learner" });
});
