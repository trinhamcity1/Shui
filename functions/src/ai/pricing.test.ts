import { callCostNanodollars, centsToNanodollars, nanodollarsToCents } from "./pricing";

describe("callCostNanodollars", () => {
  test("1M Sonnet input tokens costs exactly $2.00 — no rounding drift", () => {
    const nanodollars = callCostNanodollars("claude-sonnet-5", {
      inputTokens: 1_000_000,
      outputTokens: 0,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: 0,
    });
    expect(nanodollarsToCents(nanodollars)).toBe(200); // $2.00 = 200 cents, exact
  });

  test("1M Haiku output tokens costs exactly $5.00", () => {
    const nanodollars = callCostNanodollars("claude-haiku-4-5", {
      inputTokens: 0,
      outputTokens: 1_000_000,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: 0,
    });
    expect(nanodollarsToCents(nanodollars)).toBe(500);
  });

  test("cache write is priced at 1.25x input, cache read at 0.1x — both exact integers", () => {
    const writeOnly = callCostNanodollars("claude-sonnet-5", {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationInputTokens: 1_000_000,
      cacheReadInputTokens: 0,
    });
    const readOnly = callCostNanodollars("claude-sonnet-5", {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: 1_000_000,
    });
    expect(Number.isInteger(writeOnly)).toBe(true);
    expect(Number.isInteger(readOnly)).toBe(true);
    expect(nanodollarsToCents(writeOnly)).toBe(250); // $2.50
    expect(nanodollarsToCents(readOnly)).toBe(20); // $0.20
  });

  test("summing 1000 realistic small calls has zero cumulative rounding drift vs. one big call", () => {
    const perCall = { inputTokens: 1000, outputTokens: 150, cacheCreationInputTokens: 0, cacheReadInputTokens: 800 };
    let summed = 0;
    for (let i = 0; i < 1000; i++) {
      summed += callCostNanodollars("claude-sonnet-5", perCall);
    }
    const bulk = callCostNanodollars("claude-sonnet-5", {
      inputTokens: perCall.inputTokens * 1000,
      outputTokens: perCall.outputTokens * 1000,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: perCall.cacheReadInputTokens * 1000,
    });
    expect(summed).toBe(bulk);
  });
});

describe("centsToNanodollars / nanodollarsToCents round-trip", () => {
  test("a whole-dollar cap round-trips exactly", () => {
    expect(nanodollarsToCents(centsToNanodollars(3000))).toBe(3000); // Pyramidion's $30 cap
  });
});
