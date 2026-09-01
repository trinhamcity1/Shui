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
  test("same topic + same timing is deterministic", () => {
    expect(cacheKeyFor("compound interest", "1")).toBe(cacheKeyFor("compound interest", "1"));
  });

  test("same topic, different timing, different key — a 2-minute lesson isn't the same asset as a 1-minute one", () => {
    expect(cacheKeyFor("compound interest", "1")).not.toBe(cacheKeyFor("compound interest", "2"));
  });

  test("different topics never collide", () => {
    expect(cacheKeyFor("compound interest", "1")).not.toBe(cacheKeyFor("simple interest", "1"));
  });
});
