/**
 * The single source of truth for every tier-gated number in the app —
 * lesson generation limits/watermarking/refunds (prompts/phase-07-lessons-on-demand.md
 * §4) and the AI tutor's model/cost-cap behavior (prompts/phase-04-ai-tutor.md §3).
 * Both phases read from here; neither hardcodes a tier's numbers itself.
 */

export type TierId = "free" | "siltstone" | "obsidian" | "alabaster" | "pyramidion";

export const TIER_IDS: TierId[] = ["free", "siltstone", "obsidian", "alabaster", "pyramidion"];

export type GolpoTiming = "0.5" | "1" | "2";

export interface LikeRefundConfig {
  /** Likes needed to unlock one $refundCents credit. */
  thresholdLikes: number;
  refundCents: number;
  /** Hard ceiling on refunds granted within one billing cycle. */
  cycleCapCents: number;
  /**
   * false (Alabaster): fires once per video, the first time it crosses
   * thresholdLikes — never again for that video, regardless of further likes.
   * true (Pyramidion): fires every time the owner's *cumulative* like count
   * across all their videos crosses another multiple of thresholdLikes.
   */
  cumulative: boolean;
}

export interface TierConfig {
  id: TierId;
  displayName: string;
  /** Stripe subscription price, 0 for Free/Siltstone (no recurring fee). */
  monthlyFeeCents: number;
  /** Credit granted additively on each successful monthly charge. 0 for Free/Siltstone. */
  subscriptionCreditCents: number;
  /** Bonus applied to a $5+ top-up, e.g. 10 means $5 -> $5.50. */
  topUpBonusPercent: number;
  /** The GolpoAI `timing` value every generation at this tier uses — never user-selectable. */
  timing: GolpoTiming;
  /** true: Shui burns its watermark onto the file served/downloaded. false: the clean master is served. */
  watermarked: boolean;
  downloadable: boolean;
  likeRefund: LikeRefundConfig | null;
  aiBaselineModel: "claude-haiku-4-5" | "claude-sonnet-5";
  aiMonthlyCostCapCents: number;
  /**
   * Percent of aiMonthlyCostCapCents spent at which this tier's AI tutor
   * calls switch to Haiku for the rest of the cycle. null when the baseline
   * is already Haiku — there's nowhere lower to fall back to.
   */
  aiDowngradeThresholdPercent: number | null;
}

export const TIERS: Record<TierId, TierConfig> = {
  free: {
    id: "free",
    displayName: "Free",
    monthlyFeeCents: 0,
    subscriptionCreditCents: 0,
    topUpBonusPercent: 0,
    timing: "0.5",
    watermarked: true,
    downloadable: false,
    likeRefund: null,
    aiBaselineModel: "claude-haiku-4-5",
    aiMonthlyCostCapCents: 200,
    aiDowngradeThresholdPercent: null,
  },
  siltstone: {
    id: "siltstone",
    displayName: "Siltstone",
    monthlyFeeCents: 0,
    subscriptionCreditCents: 0,
    topUpBonusPercent: 0,
    timing: "1",
    watermarked: true,
    downloadable: true,
    likeRefund: null,
    aiBaselineModel: "claude-haiku-4-5",
    aiMonthlyCostCapCents: 200,
    aiDowngradeThresholdPercent: null,
  },
  obsidian: {
    id: "obsidian",
    displayName: "Obsidian",
    monthlyFeeCents: 2000,
    subscriptionCreditCents: 2200,
    topUpBonusPercent: 10,
    timing: "1",
    watermarked: true,
    downloadable: true,
    likeRefund: null,
    aiBaselineModel: "claude-sonnet-5",
    aiMonthlyCostCapCents: 300,
    aiDowngradeThresholdPercent: 70,
  },
  alabaster: {
    id: "alabaster",
    displayName: "Alabaster",
    monthlyFeeCents: 5000,
    subscriptionCreditCents: 5750,
    topUpBonusPercent: 15,
    timing: "2",
    watermarked: false,
    downloadable: true,
    likeRefund: { thresholdLikes: 100, refundCents: 200, cycleCapCents: 2000, cumulative: false },
    aiBaselineModel: "claude-sonnet-5",
    aiMonthlyCostCapCents: 700,
    aiDowngradeThresholdPercent: 70,
  },
  pyramidion: {
    id: "pyramidion",
    displayName: "Pyramidion",
    monthlyFeeCents: 20000,
    subscriptionCreditCents: 24000,
    topUpBonusPercent: 20,
    timing: "2",
    watermarked: false,
    downloadable: true,
    likeRefund: { thresholdLikes: 100, refundCents: 200, cycleCapCents: 2000, cumulative: true },
    aiBaselineModel: "claude-sonnet-5",
    aiMonthlyCostCapCents: 2000,
    aiDowngradeThresholdPercent: 70,
  },
};

export function tierOf(id: string | undefined | null): TierConfig {
  return TIERS[(id as TierId) ?? "free"] ?? TIERS.free;
}

/** $4/min flat, every tier — a 2x markup on GolpoAI's own $2/min at every duration. */
export const LESSON_CENTS_PER_MINUTE = 400;

/** GolpoAI's real cost, informational only — never charged to the learner directly. */
export const GOLPO_CENTS_PER_MINUTE = 200;

export function lessonCostCents(timing: GolpoTiming): number {
  return Math.round(parseFloat(timing) * LESSON_CENTS_PER_MINUTE);
}

export const MIN_TOPUP_CENTS = 500; // $5

/** Pyramidion's balance-triggered billing (phase-07-lessons-on-demand.md §4). */
export const PYRAMIDION_RECHARGE_THRESHOLD_CENTS = 24000; // $240 credit floor
export const PYRAMIDION_RECHARGE_CHARGE_CENTS = 20000; // $200 charged on recharge
export const PYRAMIDION_MAX_DELAY_DAYS = 30;

/** Alabaster/Pyramidion like-refund cycle cap, shared constant for clarity at call sites. */
export const LIKE_REFUND_CYCLE_CAP_CENTS = 2000; // $20
