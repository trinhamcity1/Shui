/**
 * Model pricing for the AI tutor's monthly cost cap (phase-04-ai-tutor.md
 * §3). Stored and computed in **nanodollars** (1e-9 USD, i.e. billionths of
 * a dollar) rather than cents, specifically so every rate below — including
 * the fractional-cent cache-write/cache-read rates — converts to an exact
 * integer with zero rounding: nanodollars-per-token is just the model's
 * dollars-per-million-tokens rate times 1,000. A per-call cost in
 * nanodollars is always a whole number; summing thousands of them across a
 * cycle never compounds rounding error the way repeatedly-rounded cents
 * would.
 */
export type AiModel = "claude-haiku-4-5" | "claude-sonnet-5";

interface ModelPricingNanodollars {
  input: number;
  /** 5-minute-TTL cache write — 1.25x the input rate, per shared/prompt-caching.md. */
  cacheWrite: number;
  /** Cache read — 0.1x the input rate. */
  cacheRead: number;
  output: number;
}

// $/1M tokens -> nanodollars/token is the same number x1000. Source: the
// claude-api skill's live-fetched pricing table (not recalled from training).
// Sonnet 5: $2.00 / $2.50 / $0.20 / $10.00. Haiku 4.5: $1.00 / $1.25 / $0.10 / $5.00.
export const MODEL_PRICING_NANODOLLARS: Record<AiModel, ModelPricingNanodollars> = {
  "claude-sonnet-5": { input: 2000, cacheWrite: 2500, cacheRead: 200, output: 10000 },
  "claude-haiku-4-5": { input: 1000, cacheWrite: 1250, cacheRead: 100, output: 5000 },
};

export interface CallUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
}

/** The exact cost of one call, in nanodollars — priced with whichever model actually served it. */
export function callCostNanodollars(model: AiModel, usage: CallUsage): number {
  const p = MODEL_PRICING_NANODOLLARS[model];
  return (
    usage.inputTokens * p.input +
    usage.outputTokens * p.output +
    usage.cacheCreationInputTokens * p.cacheWrite +
    usage.cacheReadInputTokens * p.cacheRead
  );
}

const NANODOLLARS_PER_CENT = 10_000_000;

export function nanodollarsToCents(nanodollars: number): number {
  return nanodollars / NANODOLLARS_PER_CENT;
}

export function centsToNanodollars(cents: number): number {
  return cents * NANODOLLARS_PER_CENT;
}
