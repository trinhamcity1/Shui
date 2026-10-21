import { cacheKeyFor, normalizeTopic } from "./lessonCache";

describe("normalizeTopic", () => {
  test("lowercases and trims", () => {
    expect(normalizeTopic("  How Compound Interest Works  ")).toBe("how compound interest works");
  });

  test("collapses internal whitespace", () => {
    expect(normalizeTopic("how   does   this   work")).toBe("how does this work");
  });

  test("strips punctuation", () => {
    expect(normalizeTopic("What's the deal with, like, taxes?!")).toBe("whats the deal with like taxes");
  });

  test("two differently-punctuated phrasings of the same topic normalize identically", () => {
    expect(normalizeTopic("Compound Interest!!")).toBe(normalizeTopic("compound interest"));
  });
});

describe("cacheKeyFor", () => {
  const v1 = { duration: "1", orientation: "vertical" } as const;

  test("same topic + same spec is deterministic", () => {
    expect(cacheKeyFor("compound interest", v1)).toBe(cacheKeyFor("compound interest", v1));
  });

  test("same topic, different duration, different key — a 2-minute lesson isn't the same asset as a 1-minute one", () => {
    expect(cacheKeyFor("compound interest", v1)).not.toBe(cacheKeyFor("compound interest", { ...v1, duration: "2" }));
  });

  test("same topic, different orientation, different key — a horizontal render isn't the vertical one", () => {
    expect(cacheKeyFor("compound interest", v1)).not.toBe(cacheKeyFor("compound interest", { ...v1, orientation: "horizontal" }));
  });

  test("different topics never collide", () => {
    expect(cacheKeyFor("compound interest", v1)).not.toBe(cacheKeyFor("simple interest", v1));
  });
});
