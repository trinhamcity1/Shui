import { FieldValue, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { db } from "./admin";
import { LikeRefundConfig, tierOf, TierId } from "./tiers";

export interface Wallet {
  tier: TierId;
  creditBalanceCents: number;
  hasUsedFreeLesson: boolean;
  /**
   * A stable per-user UUID passed to StoreKit as `appAccountToken` on every
   * purchase (`Product.PurchaseOption.appAccountToken`) — Apple's transaction
   * payloads carry this token back, but never a Firebase uid directly (which
   * isn't UUID-shaped anyway), so this is the only way a webhook or a
   * purchase-verification call can be tied back to a Shui account. Generated
   * once at account creation (onUserCreated.ts), never regenerated.
   */
  appAccountToken: string;
  /**
   * StoreKit's stable identifier for an active auto-renewable subscription
   * instance — the same value across every renewal of one subscription, so
   * it's what a renewal/cancellation notification is keyed on. null outside
   * Obsidian/Alabaster/Pyramidion.
   */
  appleOriginalTransactionId: string | null;
  appleSubscriptionProductId: string | null;
  likeRefundCentsThisCycle: number;
}

/**
 * Static defaults only — `appAccountToken` is deliberately excluded because
 * it must be a freshly generated UUID per user, never copied verbatim from a
 * shared constant. onUserCreated.ts spreads this and adds a real token.
 */
export const DEFAULT_WALLET: Omit<Wallet, "appAccountToken"> = {
  tier: "free",
  creditBalanceCents: 0,
  hasUsedFreeLesson: false,
  appleOriginalTransactionId: null,
  appleSubscriptionProductId: null,
  likeRefundCentsThisCycle: 0,
};

export function walletRef(uid: string) {
  return db.collection("users").doc(uid).collection("private").doc("wallet");
}

function ledgerRef(uid: string) {
  return db.collection("users").doc(uid).collection("creditTransactions").doc();
}

function appAccountTokenRef(token: string) {
  return db.collection("appAccountTokens").doc(token);
}

/** Reverse lookup for the App Store Server Notifications webhook, which only ever sees the token, never a uid. */
export async function uidForAppAccountToken(token: string): Promise<string | null> {
  const snap = await appAccountTokenRef(token).get();
  return snap.exists ? (snap.data()!.uid as string) : null;
}

/**
 * Dedupe check for Apple purchase processing — StoreKit/the notifications
 * webhook can redeliver the same transaction more than once, and a purchase
 * must never be credited twice. Callers check this before applyTopUp /
 * applySubscriptionGrant, since those functions don't dedupe themselves.
 */
export async function hasAppliedAppleTransaction(uid: string, appleTransactionId: string): Promise<boolean> {
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("creditTransactions")
    .where("relatedAppleTransactionId", "==", appleTransactionId)
    .limit(1)
    .get();
  return !snap.empty;
}

export async function readWallet(uid: string, t?: Transaction): Promise<Wallet> {
  const ref = walletRef(uid);
  const snap = t ? await t.get(ref) : await ref.get();
  // A missing wallet doc shouldn't happen (onUserCreated always seeds one),
  // but if it's ever hit, "" is a safe non-match for the appAccountToken
  // cross-check in verifyAndApplyPurchase rather than a real token value.
  if (!snap.exists) {
    return { ...DEFAULT_WALLET, appAccountToken: "" };
  }
  return { ...DEFAULT_WALLET, appAccountToken: "", ...(snap.data() as Partial<Wallet>) };
}

// ---- pure math, unit-tested directly in credits.test.ts -------------------

/**
 * $5 -> $5.50 at a 10% bonus, not $5 -> $4.50. See phase-07 §4 — "bonus",
 * never "discount": the learner always gets *more* credit than they paid,
 * the wording bug this replaces would have halved every tier's incentive.
 */
export function computeTopUpCreditCents(paidCents: number, bonusPercent: number): number {
  return Math.round(paidCents * (1 + bonusPercent / 100));
}

export function canAffordLesson(balanceCents: number, costCents: number): boolean {
  return balanceCents >= costCents;
}

export interface LikeRefundResult {
  refundCents: number;
  /** For cumulative tiers, the new "likes accounted for" marker to persist. */
  newAccountedLikes: number;
}

/**
 * config.cumulative == false (Alabaster): fires once, the first time this
 * one video's own like count crosses thresholdLikes. alreadyClaimed is a
 * per-video flag, not a count — a video that later drops under the
 * threshold and climbs back past it must not fire twice.
 *
 * config.cumulative == true (Pyramidion): fires for every new multiple of
 * thresholdLikes crossed in the owner's like count *summed across all their
 * videos*. accountedLikes is the high-water mark already paid out for;
 * newTotalLikes may jump by more than one threshold in a single update
 * (e.g. a batched counter flush), so this returns credit for every block
 * crossed, not just one.
 *
 * Both respect cycleCapCents by being capped by the caller against
 * likeRefundCentsThisCycle — this function computes the *uncapped* amount
 * earned by the like-count change alone.
 */
export function computeLikeRefund(
  config: LikeRefundConfig,
  params: { cumulative: false; alreadyClaimed: boolean; newLikeCount: number } | { cumulative: true; accountedLikes: number; newTotalLikes: number }
): LikeRefundResult {
  if (!params.cumulative) {
    if (params.alreadyClaimed || params.newLikeCount < config.thresholdLikes) {
      return { refundCents: 0, newAccountedLikes: 0 };
    }
    return { refundCents: config.refundCents, newAccountedLikes: 0 };
  }
  const blocksBefore = Math.floor(params.accountedLikes / config.thresholdLikes);
  const blocksNow = Math.floor(params.newTotalLikes / config.thresholdLikes);
  const newBlocks = Math.max(0, blocksNow - blocksBefore);
  return { refundCents: newBlocks * config.refundCents, newAccountedLikes: params.newTotalLikes };
}

/** Caps an earned refund against what's left in the cycle's $20 allowance. */
export function capRefundToCycle(earnedCents: number, alreadyGrantedThisCycleCents: number, cycleCapCents: number): number {
  const room = Math.max(0, cycleCapCents - alreadyGrantedThisCycleCents);
  return Math.min(earnedCents, room);
}

// ---- transactional writers --------------------------------------------

async function writeLedgerRow(
  t: Transaction,
  uid: string,
  row: {
    type: "topup" | "subscription_grant" | "lesson_debit" | "lesson_refund" | "like_refund" | "free_grant";
    amountCents: number;
    relatedVideoId?: string;
    /** Apple's `transactionId` (consumables) or `originalTransactionId` (subscriptions) — never a Stripe id; this app takes no user-facing payment through Stripe. */
    relatedAppleTransactionId?: string;
    note?: string;
  }
): Promise<void> {
  t.set(ledgerRef(uid), {
    ...row,
    relatedVideoId: row.relatedVideoId ?? null,
    relatedAppleTransactionId: row.relatedAppleTransactionId ?? null,
    note: row.note ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Consumes the lifetime free lesson if unused, or debits creditBalanceCents
 * for a paid tier — always *before* the caller renders or calls GolpoAI, so
 * a mid-generation failure never costs the learner quota that was never
 * actually spent (refundLesson below reverses this on a GolpoAI failure).
 */
export async function debitForLesson(
  uid: string
): Promise<{ usedFreeLesson: boolean; debitedCents: number; tier: TierId; timing: "0.5" | "1" | "2" }> {
  return db.runTransaction(async (t) => {
    const wallet = await readWallet(uid, t);

    if (!wallet.hasUsedFreeLesson && wallet.tier === "free") {
      t.set(walletRef(uid), { hasUsedFreeLesson: true, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      await writeLedgerRow(t, uid, { type: "free_grant", amountCents: 0, note: "lifetime free lesson consumed" });
      return { usedFreeLesson: true, debitedCents: 0, tier: "free", timing: "0.5" };
    }

    const tier = tierOf(wallet.tier);
    const costCents = Math.round(parseFloat(tier.timing) * 400);
    if (!canAffordLesson(wallet.creditBalanceCents, costCents)) {
      throw new HttpsError(
        "resource-exhausted",
        `You need $${(costCents / 100).toFixed(2)} of credit for a ${tier.displayName} lesson — top up to continue.`
      );
    }

    t.set(
      walletRef(uid),
      { creditBalanceCents: FieldValue.increment(-costCents), updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    await writeLedgerRow(t, uid, { type: "lesson_debit", amountCents: -costCents });
    return { usedFreeLesson: false, debitedCents: costCents, tier: tier.id, timing: tier.timing };
  });
}

/**
 * Reverses debitForLesson's charge — on a GolpoAI terminal failure (videoId
 * set), or on a Claude refusal that happened before any video doc existed
 * (videoId null). Never refunds the free lesson (nothing was charged, so
 * debitedCents is already 0 and this is a no-op).
 */
export async function refundLesson(uid: string, debitedCents: number, videoId: string | null): Promise<void> {
  if (debitedCents <= 0) return;
  await db.runTransaction(async (t) => {
    t.set(
      walletRef(uid),
      { creditBalanceCents: FieldValue.increment(debitedCents), updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    await writeLedgerRow(t, uid, { type: "lesson_refund", amountCents: debitedCents, relatedVideoId: videoId ?? undefined });
  });
}

/**
 * $5 top-up at the caller's tier bonus, credited additively. Called once the
 * server has independently verified an Apple consumable IAP transaction
 * (App Store Server API — never trust a client-reported amount).
 * `appleTransactionId` is Apple's unique `transactionId` for that purchase,
 * which callers must check against `creditTransactions` for an existing row
 * before calling this — StoreKit can redeliver the same transaction more
 * than once, and this function itself does not dedupe.
 */
export async function applyTopUp(uid: string, paidCents: number, appleTransactionId: string): Promise<void> {
  await db.runTransaction(async (t) => {
    const wallet = await readWallet(uid, t);
    const tier = tierOf(wallet.tier);
    const creditCents = computeTopUpCreditCents(paidCents, tier.topUpBonusPercent);
    t.set(
      walletRef(uid),
      { creditBalanceCents: FieldValue.increment(creditCents), updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    await writeLedgerRow(t, uid, { type: "topup", amountCents: creditCents, relatedAppleTransactionId: appleTransactionId });
  });
}

/**
 * Monthly subscription credit, granted additively — never resets what's
 * left unspent. Called on every renewal, including Pyramidion's: it is now
 * a plain auto-renewing subscription like Obsidian/Alabaster, always
 * charging its full price regardless of remaining balance — the earlier
 * balance-triggered delay/skip design doesn't exist under Apple IAP, which
 * has no mechanism for a client to skip a scheduled renewal based on
 * server-side account state.
 */
export async function applySubscriptionGrant(uid: string, tierId: TierId, appleOriginalTransactionId: string): Promise<void> {
  const tier = tierOf(tierId);
  await db.runTransaction(async (t) => {
    t.set(
      walletRef(uid),
      {
        tier: tierId,
        creditBalanceCents: FieldValue.increment(tier.subscriptionCreditCents),
        appleOriginalTransactionId,
        likeRefundCentsThisCycle: 0,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await writeLedgerRow(t, uid, {
      type: "subscription_grant",
      amountCents: tier.subscriptionCreditCents,
      relatedAppleTransactionId: appleOriginalTransactionId,
    });
  });
}
