/**
 * Testing-only: sets an account's tier directly in Firestore, bypassing
 * Apple IAP entirely. Never shipped in the app — this only runs from a
 * developer's own machine with GOOGLE_APPLICATION_CREDENTIALS pointing at a
 * service account key (same precondition as bootstrap-admin.ts), so there's
 * no new attack surface in the deployed project.
 *
 * If the account has no wallet doc yet (onUserCreated.ts seeds one on
 * account creation, but this re-creates it defensively rather than writing
 * a partial doc missing appAccountToken, which StoreKit purchases need),
 * this bootstraps a full DEFAULT_WALLET-shaped one first, exactly like
 * onUserCreated.ts does, then applies the requested tier on top.
 *
 * Usage:
 *   npm run set-tier -- <uid-or-email> <tier> [creditBalanceCents]
 *
 * tier: free | siltstone | obsidian | alabaster | pyramidion
 * creditBalanceCents: optional — set a specific balance at the same time
 *   (e.g. to test spending down credit without a real top-up purchase).
 *   Leaving it out only changes tier; the existing balance is untouched.
 */
import * as admin from "firebase-admin";
import { randomUUID } from "crypto";

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "shui-prod" });

// Mirrors functions/src/lib/tiers.ts's TIER_IDS — scripts/ is a standalone
// Node project that doesn't import functions/src, so this list is
// duplicated rather than shared. Keep it in sync if a tier is ever added.
const TIER_IDS = ["free", "siltstone", "obsidian", "alabaster", "pyramidion"] as const;
type TierId = (typeof TIER_IDS)[number];

function isTierId(value: string): value is TierId {
  return (TIER_IDS as readonly string[]).includes(value);
}

async function main(): Promise<void> {
  const [identifier, tierArg, creditArg] = process.argv.slice(2);
  if (!identifier || !tierArg || !isTierId(tierArg)) {
    console.error("Usage: npm run set-tier -- <uid-or-email> <tier> [creditBalanceCents]");
    console.error(`tier must be one of: ${TIER_IDS.join(", ")}`);
    process.exit(1);
    return;
  }

  let creditBalanceCents: number | undefined;
  if (creditArg !== undefined) {
    creditBalanceCents = Number(creditArg);
    if (!Number.isInteger(creditBalanceCents) || creditBalanceCents < 0) {
      console.error("creditBalanceCents must be a non-negative integer.");
      process.exit(1);
      return;
    }
  }

  const userRecord = identifier.includes("@")
    ? await admin.auth().getUserByEmail(identifier)
    : await admin.auth().getUser(identifier);

  const walletRef = admin.firestore().collection("users").doc(userRecord.uid).collection("private").doc("wallet");
  const snap = await walletRef.get();

  if (!snap.exists) {
    const appAccountToken = randomUUID();
    await walletRef.set({
      tier: "free",
      creditBalanceCents: 0,
      hasUsedFreeLesson: false,
      appAccountToken,
      appleOriginalTransactionId: null,
      appleSubscriptionProductId: null,
      likeRefundCentsThisCycle: 0,
      aiCycleStart: null,
      aiCycleEnd: null,
      aiSpentNanodollarsThisCycle: 0,
      cumulativeLikesReceived: 0,
      cumulativeLikesAccountedFor: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await admin.firestore().collection("appAccountTokens").doc(appAccountToken).set({
      uid: userRecord.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`No wallet existed for uid=${userRecord.uid} — bootstrapped one (this account's onUserCreated trigger may never have fired).`);
  }

  const update: Record<string, unknown> = { tier: tierArg, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
  if (creditBalanceCents !== undefined) {
    update.creditBalanceCents = creditBalanceCents;
  }
  await walletRef.set(update, { merge: true });

  console.log(`Set tier=${tierArg} for uid=${userRecord.uid} (${userRecord.email ?? "no email"}).`);
  if (creditBalanceCents !== undefined) {
    console.log(`Set creditBalanceCents=${creditBalanceCents} ($${(creditBalanceCents / 100).toFixed(2)}).`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
