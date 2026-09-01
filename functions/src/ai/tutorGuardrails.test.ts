import { formatResetCountdown, pickModel } from "./tutorGuardrails";
import { TIERS } from "../lib/tiers";
import { centsToNanodollars } from "./pricing";

describe("formatResetCountdown", () => {
  test("4h12m out rounds up to the next whole minute", () => {
    const now = new Date("2026-09-01T00:00:00Z");
    const resetAt = new Date("2026-09-01T04:12:30Z"); // 30s past 4h12m — rounds up to 4h13m
    expect(formatResetCountdown(resetAt, now)).toEqual({ hours: 4, minutes: 13 });
  });

  test("exactly on the boundary is 0h0m, not negative", () => {
    const now = new Date("2026-09-01T00:00:00Z");
    expect(formatResetCountdown(now, now)).toEqual({ hours: 0, minutes: 0 });
  });

  test("a reset time already in the past clamps to 0, never negative", () => {
    const now = new Date("2026-09-01T04:00:00Z");
    const resetAt = new Date("2026-09-01T00:00:00Z");
    expect(formatResetCountdown(resetAt, now)).toEqual({ hours: 0, minutes: 0 });
  });

  test("30 days out reports in whole hours/minutes, not days", () => {
    const now = new Date("2026-09-01T00:00:00Z");
    const resetAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    expect(formatResetCountdown(resetAt, now)).toEqual({ hours: 30 * 24, minutes: 0 });
  });
});

describe("pickModel", () => {
  test("Free/Siltstone never downgrade — already at the floor", () => {
    const cap = centsToNanodollars(TIERS.free.aiMonthlyCostCapCents);
    expect(pickModel(TIERS.free, 0, cap)).toBe("claude-haiku-4-5");
    expect(pickModel(TIERS.free, cap - 1, cap)).toBe("claude-haiku-4-5");
  });

  test("Obsidian stays on Sonnet under 70% spent", () => {
    const cap = centsToNanodollars(TIERS.obsidian.aiMonthlyCostCapCents);
    expect(pickModel(TIERS.obsidian, Math.floor(cap * 0.69), cap)).toBe("claude-sonnet-5");
  });

  test("Obsidian downgrades to Haiku at exactly 70% spent", () => {
    const cap = centsToNanodollars(TIERS.obsidian.aiMonthlyCostCapCents);
    expect(pickModel(TIERS.obsidian, Math.ceil(cap * 0.7), cap)).toBe("claude-haiku-4-5");
  });

  test("Pyramidion at $30 cap downgrades at 70% ($21) not before", () => {
    const cap = centsToNanodollars(TIERS.pyramidion.aiMonthlyCostCapCents);
    expect(TIERS.pyramidion.aiMonthlyCostCapCents).toBe(3000); // $30, bumped from $20
    expect(pickModel(TIERS.pyramidion, Math.floor(cap * 0.699), cap)).toBe("claude-sonnet-5");
    expect(pickModel(TIERS.pyramidion, Math.ceil(cap * 0.7), cap)).toBe("claude-haiku-4-5");
  });
});
