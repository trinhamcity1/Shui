import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { walletRef, readWallet } from "../lib/credits";
import { tierOf } from "../lib/tiers";
import { AiModel, callCostNanodollars, CallUsage, centsToNanodollars, nanodollarsToCents } from "./pricing";
import { TierConfig } from "../lib/tiers";

const CYCLE_DAYS = 30;

export interface ModelResolution {
  model: AiModel;
  spentCents: number;
  capCents: number;
  resetAt: Date;
}

/** Whole hours + minutes until `resetAt` — never negative, never a fraction. */
export function formatResetCountdown(resetAt: Date, now: Date): { hours: number; minutes: number } {
  const totalMinutes = Math.max(0, Math.ceil((resetAt.getTime() - now.getTime()) / 60_000));
  return { hours: Math.floor(totalMinutes / 60), minutes: totalMinutes % 60 };
}

function capExceededError(resetAt: Date, capCents: number): HttpsError {
  const { hours, minutes } = formatResetCountdown(resetAt, new Date());
  return new HttpsError(
    "resource-exhausted",
    `You've used this cycle's $${(capCents / 100).toFixed(2)} AI tutor budget — resets in ${hours}h ${minutes}m.`,
    { resetAt: resetAt.toISOString(), hours, minutes }
  );
}

/**
 * Pure decision, split out for direct unit testing: which model should
 * serve this call, given the tier's own rules and spend so far this cycle.
 */
export function pickModel(tier: TierConfig, spentNanodollars: number, capNanodollars: number): AiModel {
  if (tier.aiDowngradeThresholdPercent === null) {
    return tier.aiBaselineModel;
  }
  const thresholdNanodollars = (capNanodollars * tier.aiDowngradeThresholdPercent) / 100;
  return spentNanodollars >= thresholdNanodollars ? "claude-haiku-4-5" : tier.aiBaselineModel;
}

/**
 * Resolves which model this message should use and confirms the caller
 * hasn't already spent this cycle's cap — no daily message limit exists
 * (phase-04-ai-tutor.md §3), chat is gated purely on real dollar spend.
 *
 * For Obsidian/Alabaster/Pyramidion, once spend crosses
 * `aiDowngradeThresholdPercent` (70%) of the cap, every further call this
 * cycle is served by Haiku instead of the tier's Sonnet baseline — a
 * stretch, not a cutoff. Free/Siltstone have `aiDowngradeThresholdPercent:
 * null` (already at the floor) and just stop at 100%.
 *
 * Lazily rolls a Free/Siltstone account's cycle over the moment `now`
 * passes `aiCycleEnd` — there is no external renewal event for those tiers
 * to reset on, so this function is itself the reset mechanism, same
 * discipline the original free-lesson cap used. Subscribed tiers get their
 * cycle reset by applySubscriptionGrant on a real Apple renewal instead;
 * this function only ever *reads* their cycle state.
 */
export async function resolveModelForMessage(uid: string): Promise<ModelResolution> {
  const wallet = await readWallet(uid);
  const tier = tierOf(wallet.tier);
  const now = new Date();

  let cycleEnd = wallet.aiCycleEnd?.toDate() ?? null;
  let spentNanodollars = wallet.aiSpentNanodollarsThisCycle ?? 0;

  if (!cycleEnd || now >= cycleEnd) {
    cycleEnd = new Date(now.getTime() + CYCLE_DAYS * 24 * 60 * 60 * 1000);
    spentNanodollars = 0;
    await walletRef(uid).set(
      { aiCycleStart: now, aiCycleEnd: cycleEnd, aiSpentNanodollarsThisCycle: 0, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  const capNanodollars = centsToNanodollars(tier.aiMonthlyCostCapCents);
  if (spentNanodollars >= capNanodollars) {
    throw capExceededError(cycleEnd, tier.aiMonthlyCostCapCents);
  }

  return {
    model: pickModel(tier, spentNanodollars, capNanodollars),
    spentCents: nanodollarsToCents(spentNanodollars),
    capCents: tier.aiMonthlyCostCapCents,
    resetAt: cycleEnd,
  };
}

/** Records one call's real cost against the cycle total, priced with whichever model actually served it. */
export async function recordAiUsage(uid: string, model: AiModel, usage: CallUsage): Promise<void> {
  const costNanodollars = callCostNanodollars(model, usage);
  await walletRef(uid).set(
    { aiSpentNanodollarsThisCycle: FieldValue.increment(costNanodollars), updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
}
