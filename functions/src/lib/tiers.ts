/**
 * The single source of truth for every tier-gated number in the app —
 * lesson generation limits/watermarking/refunds (prompts/phase-07-lessons-on-demand.md
 * §4) and the AI tutor's model/cost-cap behavior (prompts/phase-04-ai-tutor.md §3).
 * Both phases read from here; neither hardcodes a tier's numbers itself.
 */

export type TierId = "free" | "siltstone" | "obsidian" | "alabaster" | "pyramidion";

export const TIER_IDS: TierId[] = ["free", "siltstone", "obsidian", "alabaster", "pyramidion"];

/** The GolpoAI `timing` buckets this app actually sends — a subset of what Golpo supports. */
export type GolpoTiming = "0.5" | "1" | "2";

/**
 * What the learner picks, in minutes, spelled the way Golpo spells `timing`.
 * "1.5" is not a Golpo timing value — it renders as `timing: "2"` with a
 * script sized for 90 seconds. Golpo's docs only require `timing` to be
 * >= the script's estimated length, so the shorter script is what sets the
 * real length (see golpoTimingFor).
 */
export const LESSON_DURATIONS = ["0.5", "1", "1.5", "2"] as const;
export type LessonDuration = (typeof LESSON_DURATIONS)[number];

/** Golpo's only two real output sizes: vertical 1024×1536, horizontal 1536×1024. */
export const LESSON_ORIENTATIONS = ["vertical", "horizontal"] as const;
export type LessonOrientation = (typeof LESSON_ORIENTATIONS)[number];

/** The two things that make one rendered lesson a different asset from another on the same topic. */
export interface LessonSpec {
  duration: LessonDuration;
  orientation: LessonOrientation;
}

export function golpoTimingFor(duration: LessonDuration): GolpoTiming {
  return duration === "1.5" ? "2" : duration;
}

export function durationLabel(duration: LessonDuration): string {
  switch (duration) {
    case "0.5":
      return "30-second";
    case "1":
      return "1-minute";
    case "1.5":
      return "90-second";
    case "2":
      return "2-minute";
  }
}

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
  /** The longest lesson this tier may generate — every shorter LESSON_DURATIONS entry is allowed too. */
  maxDuration: LessonDuration;
  /** This tier's per-minute lesson price; any duration's cost is pro-rated from it. */
  lessonCentsPerMinute: number;
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

/** The default per-minute lesson rate ($4/min) — a 2x markup on GolpoAI's own $2/min. Every tier uses it today; each tier reads it via its own `lessonCentsPerMinute` so a tier can be repriced alone. */
export const LESSON_CENTS_PER_MINUTE = 400;

export const TIERS: Record<TierId, TierConfig> = {
  free: {
    id: "free",
    displayName: "Free",
    monthlyFeeCents: 0,
    subscriptionCreditCents: 0,
    topUpBonusPercent: 0,
    maxDuration: "0.5",
    lessonCentsPerMinute: LESSON_CENTS_PER_MINUTE,
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
    maxDuration: "1",
    lessonCentsPerMinute: LESSON_CENTS_PER_MINUTE,
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
    maxDuration: "1",
    lessonCentsPerMinute: LESSON_CENTS_PER_MINUTE,
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
    maxDuration: "2",
    lessonCentsPerMinute: LESSON_CENTS_PER_MINUTE,
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
    maxDuration: "2",
    lessonCentsPerMinute: LESSON_CENTS_PER_MINUTE,
    watermarked: false,
    downloadable: true,
    likeRefund: { thresholdLikes: 100, refundCents: 200, cycleCapCents: 2000, cumulative: true },
    aiBaselineModel: "claude-sonnet-5",
    aiMonthlyCostCapCents: 3000, // $30 — bumped from $20
    aiDowngradeThresholdPercent: 70,
  },
};

export function tierOf(id: string | undefined | null): TierConfig {
  return TIERS[(id as TierId) ?? "free"] ?? TIERS.free;
}

/** GolpoAI's real cost, informational only — never charged to the learner directly. */
export const GOLPO_CENTS_PER_MINUTE = 200;

export function isDurationAllowed(tier: TierConfig, duration: LessonDuration): boolean {
  return parseFloat(duration) <= parseFloat(tier.maxDuration);
}

/** Pro-rated from the tier's own rate: at $4/min, 30s is $2 and 90s is $6. */
export function lessonCostCents(tier: TierConfig, duration: LessonDuration): number {
  return Math.round(parseFloat(duration) * tier.lessonCentsPerMinute);
}

/** The cheapest tier that unlocks `duration` — for "needs Alabaster" copy. */
export function minimumTierFor(duration: LessonDuration): TierConfig {
  return TIER_IDS.map((id) => TIERS[id]).find((tier) => isDurationAllowed(tier, duration)) ?? TIERS.pyramidion;
}

export const MIN_TOPUP_CENTS = 500; // $5

/**
 * Alabaster/Pyramidion like-refund cycle cap, shared constant for clarity at
 * call sites.
 */
export const LIKE_REFUND_CYCLE_CAP_CENTS = 2000; // $20
