import { golpoTimingFor, isDurationAllowed, lessonCostCents, LESSON_DURATIONS, minimumTierFor, TIERS } from "./tiers";

describe("lessonCostCents", () => {
  test("pro-rates from the tier's own per-minute rate", () => {
    expect(lessonCostCents(TIERS.obsidian, "0.5")).toBe(200);
    expect(lessonCostCents(TIERS.obsidian, "1")).toBe(400);
    expect(lessonCostCents(TIERS.alabaster, "1.5")).toBe(600);
    expect(lessonCostCents(TIERS.alabaster, "2")).toBe(800);
  });

  test("a tier repriced alone changes only its own cost", () => {
    const discounted = { ...TIERS.pyramidion, lessonCentsPerMinute: 300 };
    expect(lessonCostCents(discounted, "0.5")).toBe(150);
    expect(lessonCostCents(TIERS.alabaster, "0.5")).toBe(200);
  });
});

describe("isDurationAllowed", () => {
  test("each tier allows every length up to its max, and nothing above", () => {
    expect(LESSON_DURATIONS.filter((d) => isDurationAllowed(TIERS.free, d))).toEqual(["0.5"]);
    expect(LESSON_DURATIONS.filter((d) => isDurationAllowed(TIERS.siltstone, d))).toEqual(["0.5", "1"]);
    expect(LESSON_DURATIONS.filter((d) => isDurationAllowed(TIERS.obsidian, d))).toEqual(["0.5", "1"]);
    expect(LESSON_DURATIONS.filter((d) => isDurationAllowed(TIERS.alabaster, d))).toEqual(["0.5", "1", "1.5", "2"]);
    expect(LESSON_DURATIONS.filter((d) => isDurationAllowed(TIERS.pyramidion, d))).toEqual(["0.5", "1", "1.5", "2"]);
  });
});

describe("minimumTierFor", () => {
  test("names the cheapest tier that unlocks a length", () => {
    expect(minimumTierFor("0.5").id).toBe("free");
    expect(minimumTierFor("1").id).toBe("siltstone");
    expect(minimumTierFor("1.5").id).toBe("alabaster");
    expect(minimumTierFor("2").id).toBe("alabaster");
  });
});

describe("golpoTimingFor", () => {
  test("90 seconds renders in Golpo's 2-minute bucket; every other length maps to itself", () => {
    expect(golpoTimingFor("0.5")).toBe("0.5");
    expect(golpoTimingFor("1")).toBe("1");
    expect(golpoTimingFor("1.5")).toBe("2");
    expect(golpoTimingFor("2")).toBe("2");
  });
});
