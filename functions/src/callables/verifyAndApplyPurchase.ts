import { onCall, HttpsError } from "firebase-functions/v2/https";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { VerifyAndApplyPurchaseInputSchema } from "../schemas/callableInputs";
import { actionForProductId, getSignedDataVerifier } from "../lib/appleIap";
import { applySubscriptionGrant, applyTopUp, hasAppliedAppleTransaction, readWallet } from "../lib/credits";
import { Type } from "@apple/app-store-server-library";

export interface VerifyAndApplyPurchaseResult {
  applied: boolean;
  tier?: string;
}

/**
 * The fast path for crediting a purchase — called right after
 * `Product.purchase()` succeeds on the client, with the transaction's raw
 * signed JWS (`VerificationResult.jwsRepresentation`, never a parsed/
 * client-trusted amount). The App Store Server Notifications webhook
 * (appStoreServerNotifications.ts) is the durable backstop for anything
 * this path misses — both apply the exact same dedupe-then-credit logic, so
 * whichever fires first wins and the other is a no-op.
 */
export async function runVerifyAndApplyPurchase(
  uid: string,
  signedTransactionInfo: string
): Promise<VerifyAndApplyPurchaseResult> {
  const transaction = await getSignedDataVerifier().verifyAndDecodeTransaction(signedTransactionInfo);

  if (!transaction.transactionId || !transaction.productId) {
    throw new HttpsError("invalid-argument", "The purchase receipt is missing required fields.");
  }

  // A valid Apple-signed transaction proves the purchase happened, but not
  // that it belongs to *this* caller — a leaked or replayed JWS from a
  // different Shui account would otherwise still pass signature
  // verification. appAccountToken is the tie-breaker: it must match the
  // caller's own wallet token, set once at account creation.
  const wallet = await readWallet(uid);
  if (!wallet.appAccountToken || transaction.appAccountToken !== wallet.appAccountToken) {
    throw new HttpsError("permission-denied", "This purchase does not belong to your account.");
  }

  const alreadyApplied = await hasAppliedAppleTransaction(uid, transaction.transactionId);
  if (alreadyApplied) {
    return { applied: false }; // already credited, by this path or the webhook
  }

  const action = actionForProductId(transaction.productId);
  if (!action) {
    throw new HttpsError("failed-precondition", `Unrecognized product: ${transaction.productId}`);
  }

  if (action.kind === "topup") {
    if (transaction.type !== Type.CONSUMABLE) {
      throw new HttpsError("failed-precondition", "Expected a consumable transaction for a top-up product.");
    }
    await applyTopUp(uid, action.amountCents, transaction.transactionId);
    return { applied: true };
  }

  if (transaction.type !== Type.AUTO_RENEWABLE_SUBSCRIPTION || !transaction.originalTransactionId) {
    throw new HttpsError("failed-precondition", "Expected an auto-renewable subscription transaction.");
  }
  await applySubscriptionGrant(uid, action.tier, transaction.originalTransactionId);
  return { applied: true, tier: action.tier };
}

export const verifyAndApplyPurchase = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(VerifyAndApplyPurchaseInputSchema, request.data);
  return runVerifyAndApplyPurchase(uid, input.signedTransactionInfo);
});
