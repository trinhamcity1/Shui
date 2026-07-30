/**
 * Grants the first `admin` custom claim, breaking the bootstrap cycle: the
 * `assignRole` callable requires an admin caller, so the very first admin
 * can't come from it. Run once locally against a real project (with
 * GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key that is
 * never committed) or against the emulator suite for local testing.
 *
 * Usage:
 *   npm run bootstrap-admin -- <uid-or-email>
 */
import * as admin from "firebase-admin";

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "shui-prod" });

async function main(): Promise<void> {
  const identifier = process.argv[2];
  if (!identifier) {
    console.error("Usage: npm run bootstrap-admin -- <uid-or-email>");
    process.exit(1);
    return;
  }

  const userRecord = identifier.includes("@")
    ? await admin.auth().getUserByEmail(identifier)
    : await admin.auth().getUser(identifier);

  const existingClaims = userRecord.customClaims ?? {};
  await admin.auth().setCustomUserClaims(userRecord.uid, { ...existingClaims, role: "admin" });
  await admin.firestore().collection("users").doc(userRecord.uid).set({ role: "admin" }, { merge: true });

  console.log(`Granted admin to uid=${userRecord.uid} (${userRecord.email ?? "no email"}).`);
  console.log(`Re-run seed:civics with SEED_ADMIN_UID=${userRecord.uid} to own the seeded civics topic.`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
