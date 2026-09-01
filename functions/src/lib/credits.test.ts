import { canAffordLesson, capRefundToCycle, computeLikeRefund, computeTopUpCreditCents } from "./credits";
import { TIERS } from "./tiers";

describe("computeTopUpCreditCents", () => {
  test("0% bonus (Siltstone) is 1:1", () => {
    expect(computeTopUpCreditCents(500, 0)).toBe(500);
  });
  test("10% bonus (Obsidian): $5 -> $5.50, not $4.50", () => {
    expect(computeTopUpCreditCents(500, 10)).toBe(550);
  });
  test("15% bonus (Alabaster): $5 -> $5.75", () => {
    expect(computeTopUpCreditCents(500, 15)).toBe(575);
  });
  test("20% bonus (Pyramidion): $5 -> $6.00", () => {
    expect(computeTopUpCreditCents(500, 20)).toBe(600);
  });
});

describe("canAffordLesson", () => {
  test("exact balance affords the lesson", () => {
    expect(canAffordLesson(400, 400)).toBe(true);
  });
  test("insufficient balance refuses", () => {
    expect(canAffordLesson(399, 400)).toBe(false);
  });
});

describe("computeLikeRefund — Alabaster (one-time per video)", () => {
  const config = TIERS.alabaster.likeRefund!;

  test("crossing 100 for the first time earns $2", () => {
    const result = computeLikeRefund(config, { cumulative: false, alreadyClaimed: false, newLikeCount: 100 });
    expect(result.refundCents).toBe(200);
  });
  test("under threshold earns nothing", () => {
    const result = computeLikeRefund(config, { cumulative: false, alreadyClaimed: false, newLikeCount: 99 });
    expect(result.refundCents).toBe(0);
  });
  test("already claimed never fires again, even at 500 likes", () => {
    const result = computeLikeRefund(config, { cumulative: false, alreadyClaimed: true, newLikeCount: 500 });
    expect(result.refundCents).toBe(0);
  });
});

describe("computeLikeRefund — Pyramidion (cumulative across videos)", () => {
  const config = TIERS.pyramidion.likeRefund!;

  test("first block of 100 earns $2", () => {
    const result = computeLikeRefund(config, { cumulative: true, accountedLikes: 0, newTotalLikes: 100 });
    expect(result.refundCents).toBe(200);
    expect(result.newAccountedLikes).toBe(100);
  });
  test("jumping from 80 to 250 (a batched counter flush) earns two blocks, not one", () => {
    const result = computeLikeRefund(config, { cumulative: true, accountedLikes: 80, newTotalLikes: 250 });
    expect(result.refundCents).toBe(400); // 100 and 200 crossed; 250 hasn't crossed 300 yet
    expect(result.newAccountedLikes).toBe(250);
  });
  test("moving within the same block earns nothing", () => {
    const result = computeLikeRefund(config, { cumulative: true, accountedLikes: 120, newTotalLikes: 150 });
    expect(result.refundCents).toBe(0);
  });
});

describe("capRefundToCycle", () => {
  test("earned amount under the cap passes through unchanged", () => {
    expect(capRefundToCycle(200, 0, 2000)).toBe(200);
  });
  test("earned amount is trimmed to whatever room remains", () => {
    expect(capRefundToCycle(400, 1900, 2000)).toBe(100);
  });
  test("no room left earns nothing further, even from a fresh crossing", () => {
    expect(capRefundToCycle(200, 2000, 2000)).toBe(0);
  });
});
