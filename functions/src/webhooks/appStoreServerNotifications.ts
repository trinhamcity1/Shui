import { onRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { NotificationTypeV2 } from "@apple/app-store-server-library";
import { actionForProductId, getSignedDataVerifier } from "../lib/appleIap";
import { applySubscriptionGrant, hasAppliedAppleTransaction, uidForAppAccountToken, walletRef } from "../lib/credits";

/**
 * App Store Server Notifications V2 — the durable backstop for crediting a
 * purchase, catching renewals, cancellations, and refunds: everything
 * `verifyAndApplyPurchase`'s fast client-initiated path can miss (app killed
 * mid-purchase, a network drop right after `Product.purchase()` returns) and
 * everything that only ever happens server-side to begin with (a renewal,
 * nobody's phone is open for that). Configure this URL in App Store Connect
 * under App Information -> App Store Server Notifications, production and
 * sandbox both.
 *
 * Every code path here `res.status(200)`s even when there's nothing to do —
 * Apple retries on anything else, and most notification types genuinely
 * carry nothing actionable for Shui's wallet.
 */
export const appStoreServerNotifications = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const signedPayload = (req.body as { signedPayload?: unknown } | undefined)?.signedPayload;
  if (typeof signedPayload !== "string") {
    res.status(400).send("Missing signedPayload");
    return;
  }

  let notification;
  try {
    notification = await getSignedDataVerifier().verifyAndDecodeNotification(signedPayload);
  } catch {
    res.status(400).send("Invalid signature");
    return;
  }

  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (!signedTransactionInfo) {
    res.status(200).send("OK"); // e.g. a TEST notification — nothing to apply
    return;
  }

  const transaction = await getSignedDataVerifier().verifyAndDecodeTransaction(signedTransactionInfo);
  if (!transaction.appAccountToken || !transaction.transactionId || !transaction.productId) {
    res.status(200).send("OK");
    return;
  }

  const uid = await uidForAppAccountToken(transaction.appAccountToken);
  if (!uid) {
    res.status(200).send("OK"); // unrecognized token — nothing more we can do with this
    return;
  }

  const action = actionForProductId(transaction.productId);
  // Consumable top-ups are handled entirely by verifyAndApplyPurchase's fast
  // path — a consumable never renews, so there is nothing this webhook
  // needs to do for one beyond what that path already applied.
  if (!action || action.kind !== "subscription") {
    res.status(200).send("OK");
    return;
  }

  switch (notification.notificationType) {
    case NotificationTypeV2.SUBSCRIBED:
    case NotificationTypeV2.DID_RENEW: {
      const alreadyApplied = await hasAppliedAppleTransaction(uid, transaction.transactionId);
      if (!alreadyApplied && transaction.originalTransactionId) {
        await applySubscriptionGrant(uid, action.tier, transaction.originalTransactionId);
      }
      break;
    }
    case NotificationTypeV2.EXPIRED:
    case NotificationTypeV2.DID_FAIL_TO_RENEW: {
      // Lapsed subscription: drop to Siltstone going forward. Unspent
      // credit is untouched — it never expires regardless of tier, per
      // phase-07 §4's "Billing mechanics".
      await walletRef(uid).set({ tier: "siltstone", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      break;
    }
    case NotificationTypeV2.REFUND:
    case NotificationTypeV2.REVOKE:
      // NOT IMPLEMENTED: reversing a refunded grant correctly requires
      // knowing whether *that specific grant's* credit has already been
      // spent out of a pooled, fungible balance — not a small addition.
      // Per phase-07 §"Billing mechanics", a refund after the credit is
      // already spent is accepted loss, never clawed into a negative
      // balance; an unspent-refund reversal is a real gap, flagged here
      // rather than shipped half-correct.
      break;
    default:
      break;
  }

  res.status(200).send("OK");
});
