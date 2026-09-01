import { ageInDays, computeSocialScore } from "./socialScore";

describe("computeSocialScore", () => {
  test("more likes always scores higher than fewer, all else equal", () => {
    const base = { likeCount: 10, commentCount: 5, viewCount: 100, ageInDays: 0 };
    const more = { ...base, likeCount: 50 };
    expect(computeSocialScore(more)).toBeGreaterThan(computeSocialScore(base));
  });

  test("likes weigh more than comments, which weigh more than views, at equal counts", () => {
    const likesOnly = computeSocialScore({ likeCount: 20, commentCount: 0, viewCount: 0, ageInDays: 0 });
    const commentsOnly = computeSocialScore({ likeCount: 0, commentCount: 20, viewCount: 0, ageInDays: 0 });
    const viewsOnly = computeSocialScore({ likeCount: 0, commentCount: 0, viewCount: 20, ageInDays: 0 });
    expect(likesOnly).toBeGreaterThan(commentsOnly);
    expect(commentsOnly).toBeGreaterThan(viewsOnly);
  });

  test("an older video scores lower than an identical fresh one", () => {
    const fresh = computeSocialScore({ likeCount: 10, commentCount: 2, viewCount: 50, ageInDays: 0 });
    const old = computeSocialScore({ likeCount: 10, commentCount: 2, viewCount: 50, ageInDays: 30 });
    expect(old).toBeLessThan(fresh);
  });

  test("zero engagement is a real, finite number, not NaN or -Infinity", () => {
    const score = computeSocialScore({ likeCount: 0, commentCount: 0, viewCount: 0, ageInDays: 0 });
    expect(Number.isFinite(score)).toBe(true);
    expect(score).toBe(0);
  });

  test("negative counts (shouldn't happen, but never trusted blindly) don't produce NaN", () => {
    const score = computeSocialScore({ likeCount: -1, commentCount: -1, viewCount: -1, ageInDays: -5 });
    expect(Number.isFinite(score)).toBe(true);
  });
});

describe("ageInDays", () => {
  test("30 days apart is exactly 30", () => {
    const now = new Date("2026-09-01T00:00:00Z");
    const publishedAt = new Date("2026-08-02T00:00:00Z");
    expect(ageInDays(publishedAt, now)).toBeCloseTo(30, 5);
  });

  test("a publish time in the future (clock skew) clamps to 0, not negative", () => {
    const now = new Date("2026-09-01T00:00:00Z");
    const publishedAt = new Date("2026-09-05T00:00:00Z");
    expect(ageInDays(publishedAt, now)).toBe(0);
  });
});
