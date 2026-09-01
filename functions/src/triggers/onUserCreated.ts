import { FieldValue } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { auth } from "../lib/admin";
import { DEFAULT_WALLET, walletRef } from "../lib/credits";

/**
 * Firestore rules require users/{uid} to be created with role: "learner"
 * already in the document (a display mirror), but the custom claim that
 * rules actually trust (request.auth.token.role) can only be set here, via
 * the Admin SDK, once the account exists.
 *
 * Also seeds users/{uid}/private/wallet (phase-07-lessons-on-demand.md §4) —
 * kept in its own owner-only-read subcollection rather than on this public
 * profile doc, since creditBalanceCents/tier/stripeCustomerId must never
 * ride along on a read any signed-in or anonymous client can already make
 * against users/{uid}.
 */
export const onUserCreated = onDocumentCreated("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const userRecord = await auth.getUser(uid);
  if (!userRecord.customClaims?.role) {
    await auth.setCustomUserClaims(uid, { ...userRecord.customClaims, role: "learner" });
  }
  await walletRef(uid).set({ ...DEFAULT_WALLET, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
});
