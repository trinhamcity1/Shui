import { DEFAULT_LOW_BALANCE_THRESHOLD_CENTS, isBelowThreshold, isExhausted, ProviderBudget, remainingCents } from "./providerBudgets";

function budget(overrides: Partial<ProviderBudget> = {}): ProviderBudget {
  return {
    provider: "golpo",
    toppedUpCentsAllTime: 20000,
    spentCentsAllTime: 0,
    lowBalanceThresholdCents: DEFAULT_LOW_BALANCE_THRESHOLD_CENTS,
    alertActive: false,
    updatedAt: null,
    ...overrides,
  };
}

describe("remainingCents", () => {
  test("topped up minus spent", () => {
    expect(remainingCents(budget({ toppedUpCentsAllTime: 20000, spentCentsAllTime: 15000 }))).toBe(5000);
  });
  test("can go negative if spend somehow exceeds tracked top-ups", () => {
    expect(remainingCents(budget({ toppedUpCentsAllTime: 100, spentCentsAllTime: 300 }))).toBe(-200);
  });
});

describe("isExhausted", () => {
  test("false while any balance remains", () => {
    expect(isExhausted(budget({ toppedUpCentsAllTime: 100, spentCentsAllTime: 99 }))).toBe(false);
  });
  test("true at exactly zero remaining", () => {
    expect(isExhausted(budget({ toppedUpCentsAllTime: 100, spentCentsAllTime: 100 }))).toBe(true);
  });
  test("true when spend has exceeded top-ups", () => {
    expect(isExhausted(budget({ toppedUpCentsAllTime: 100, spentCentsAllTime: 150 }))).toBe(true);
  });
});

describe("isBelowThreshold", () => {
  test("false comfortably above threshold", () => {
    expect(isBelowThreshold(budget({ toppedUpCentsAllTime: 20000, spentCentsAllTime: 5000, lowBalanceThresholdCents: 5000 }))).toBe(false);
  });
  test("true once remaining drops to the threshold", () => {
    expect(isBelowThreshold(budget({ toppedUpCentsAllTime: 20000, spentCentsAllTime: 15000, lowBalanceThresholdCents: 5000 }))).toBe(true);
  });
  test("true when already exhausted", () => {
    expect(isBelowThreshold(budget({ toppedUpCentsAllTime: 100, spentCentsAllTime: 100, lowBalanceThresholdCents: 5000 }))).toBe(true);
  });
});
