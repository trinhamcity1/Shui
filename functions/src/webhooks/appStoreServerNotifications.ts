import { onRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { NotificationTypeV2 } from "@apple/app-store-server-library";
import { actionForProductId, verifyNotification, verifyTransaction } from "../lib/appleIap";
import {
  applySubscriptionGrant,
  hasAppliedAppleTransaction,
  reverseGrantForAppleTransaction,
  uidForAppAccountToken,
  walletRef,
} from "../lib/credits";

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
    notification = await verifyNotification(signedPayload);
  } catch {
    res.status(400).send("Invalid signature");
    return;
  }

  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (!signedTransactionInfo) {
    res.status(200).send("OK"); // e.g. a TEST notification — nothing to apply
    return;
  }

  const transaction = await verifyTransaction(signedTransactionInfo);
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
  if (!action) {
    res.status(200).send("OK");
    return;
  }

  switch (notification.notificationType) {
    case NotificationTypeV2.SUBSCRIBED:
    case NotificationTypeV2.DID_RENEW: {
      // Consumable top-ups are handled entirely by verifyAndApplyPurchase's
      // fast path — a consumable never renews, so there is nothing to do
      // here for one.
      if (action.kind !== "subscription") break;
      const alreadyApplied = await hasAppliedAppleTransaction(uid, transaction.transactionId);
      if (!alreadyApplied && transaction.originalTransactionId) {
        await applySubscriptionGrant(uid, action.tier, transaction.transactionId, transaction.originalTransactionId);
      }
      break;
    }
    case NotificationTypeV2.EXPIRED:
    case NotificationTypeV2.DID_FAIL_TO_RENEW: {
      if (action.kind !== "subscription") break;
      // Lapsed subscription: drop to Siltstone going forward. Unspent
      // credit is untouched — it never expires regardless of tier, per
      // phase-07 §4's "Billing mechanics".
      await walletRef(uid).set({ tier: "siltstone", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      break;
    }
    case NotificationTypeV2.REFUND:
    case NotificationTypeV2.REVOKE:
      // Applies to both a top-up and a subscription grant — reverses
      // whatever's left of that specific transaction's credit, capped at
      // the current balance so it never goes negative, and drops the tier
      // only if this is the subscription lineage the wallet is currently
      // on. See reverseGrantForAppleTransaction's own doc comment.
      await reverseGrantForAppleTransaction(
        uid,
        transaction.transactionId,
        action.kind === "subscription" ? transaction.originalTransactionId ?? null : null
      );
      break;
    default:
      break;
  }

  res.status(200).send("OK");
});
