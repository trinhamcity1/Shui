import { generateRawApiKey, hashApiKey, nextRateLimitWindow, API_KEY_RATE_LIMIT_PER_HOUR, API_KEY_RATE_LIMIT_WINDOW_MS } from "./apiKeys";

describe("generateRawApiKey", () => {
  test("starts with the shui_live_ prefix", () => {
    expect(generateRawApiKey()).toMatch(/^shui_live_/);
  });
  test("two calls never collide", () => {
    expect(generateRawApiKey()).not.toBe(generateRawApiKey());
  });
});

describe("hashApiKey", () => {
  test("is deterministic for the same input", () => {
    const key = generateRawApiKey();
    expect(hashApiKey(key)).toBe(hashApiKey(key));
  });
  test("different keys hash to different values", () => {
    expect(hashApiKey(generateRawApiKey())).not.toBe(hashApiKey(generateRawApiKey()));
  });
  test("never returns the raw key itself", () => {
    const key = generateRawApiKey();
    expect(hashApiKey(key)).not.toBe(key);
  });
});

describe("nextRateLimitWindow", () => {
  const now = 1_000_000;

  test("a brand-new key (no current window) is allowed and opens a fresh window", () => {
    const result = nextRateLimitWindow(null, now);
    expect(result.allowed).toBe(true);
    expect(result.window).toEqual({ windowStartMs: now, count: 1 });
  });

  test("under the limit within the same window increments the count", () => {
    const current = { windowStartMs: now - 1000, count: 5 };
    const result = nextRateLimitWindow(current, now);
    expect(result.allowed).toBe(true);
    expect(result.window).toEqual({ windowStartMs: now - 1000, count: 6 });
  });

  test("at the limit within the same window is refused, unchanged", () => {
    const current = { windowStartMs: now - 1000, count: API_KEY_RATE_LIMIT_PER_HOUR };
    const result = nextRateLimitWindow(current, now);
    expect(result.allowed).toBe(false);
    expect(result.window).toEqual(current);
  });

  test("a window that has fully expired resets, even if it was maxed out", () => {
    const current = { windowStartMs: now - API_KEY_RATE_LIMIT_WINDOW_MS, count: API_KEY_RATE_LIMIT_PER_HOUR };
    const result = nextRateLimitWindow(current, now);
    expect(result.allowed).toBe(true);
    expect(result.window).toEqual({ windowStartMs: now, count: 1 });
  });

  test("a custom limit/window is honored", () => {
    const result = nextRateLimitWindow({ windowStartMs: now - 10, count: 2 }, now, 1000, 2);
    expect(result.allowed).toBe(false);
  });
});
