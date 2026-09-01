import { HttpsError } from "firebase-functions/v2/https";
import { parseGeneratedLesson, runGenerateLesson } from "./generateLesson";
import { FakeModelClient } from "./modelClient";
import { scriptCharBudget } from "../lib/golpo";

const VALID_RESPONSE = JSON.stringify({
  refused: false,
  categoryId: "science-tech",
  script: "Photosynthesis turns light into sugar. Plants use chlorophyll to capture light energy.",
  quiz: {
    questions: [
      {
        id: "q1",
        prompt: "What does photosynthesis produce?",
        options: [
          { id: "a", text: "Sugar" },
          { id: "b", text: "Salt" },
        ],
        correctOptionIds: ["a"],
        requiredCorrectCount: 1,
        explanation: "Plants convert light energy into sugar via photosynthesis.",
        orderIndex: 0,
      },
    ],
  },
});

describe("parseGeneratedLesson", () => {
  test("parses a valid lesson", () => {
    const result = parseGeneratedLesson(VALID_RESPONSE, "1");
    expect(result.refused).toBe(false);
    if (!result.refused) {
      expect(result.categoryId).toBe("science-tech");
      expect(result.questions).toHaveLength(1);
    }
  });

  test("strips a markdown fence the model wasn't supposed to add", () => {
    const fenced = "```json\n" + VALID_RESPONSE + "\n```";
    const result = parseGeneratedLesson(fenced, "1");
    expect(result.refused).toBe(false);
  });

  test("passes through an explicit refusal", () => {
    const refusal = JSON.stringify({ refused: true, reason: "Not something we can teach responsibly." });
    const result = parseGeneratedLesson(refusal, "1");
    expect(result).toEqual({ refused: true, reason: "Not something we can teach responsibly." });
  });

  test("rejects an invalid category slug (internal error, not a silent pass-through)", () => {
    const bad = JSON.stringify({ ...JSON.parse(VALID_RESPONSE), categoryId: "not-a-real-category" });
    expect(() => parseGeneratedLesson(bad, "1")).toThrow(HttpsError);
  });

  test("rejects a script over the timing's character budget", () => {
    const over = JSON.stringify({
      ...JSON.parse(VALID_RESPONSE),
      script: "x".repeat(scriptCharBudget("0.5") + 1),
    });
    expect(() => parseGeneratedLesson(over, "0.5")).toThrow(HttpsError);
  });

  test("rejects a malformed quiz the same way saveQuiz would (no correct option present)", () => {
    const bad = JSON.parse(VALID_RESPONSE);
    bad.quiz.questions[0].correctOptionIds = ["not-an-option-id"];
    expect(() => parseGeneratedLesson(JSON.stringify(bad), "1")).toThrow(HttpsError);
  });

  test("unparsable JSON throws rather than silently returning garbage", () => {
    expect(() => parseGeneratedLesson("not json at all", "1")).toThrow(HttpsError);
  });
});

describe("runGenerateLesson", () => {
  test("wires a scripted model response through end to end", async () => {
    const fake = new FakeModelClient(VALID_RESPONSE);
    const result = await runGenerateLesson("photosynthesis", "1", fake);
    expect(result.refused).toBe(false);
  });
});
