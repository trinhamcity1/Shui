import { HttpsError } from "firebase-functions/v2/https";
import { parseRegeneratedQuiz, runRegenerateQuiz } from "./regenerateQuiz";
import { FakeModelClient } from "./modelClient";

const VALID_RESPONSE = JSON.stringify({
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
});

describe("parseRegeneratedQuiz", () => {
  test("parses a valid quiz", () => {
    const questions = parseRegeneratedQuiz(VALID_RESPONSE);
    expect(questions).toHaveLength(1);
    expect(questions[0]!.prompt).toBe("What does photosynthesis produce?");
  });

  test("strips a markdown fence the model wasn't supposed to add", () => {
    const fenced = "```json\n" + VALID_RESPONSE + "\n```";
    expect(parseRegeneratedQuiz(fenced)).toHaveLength(1);
  });

  test("rejects a malformed quiz (no correct option present)", () => {
    const bad = JSON.parse(VALID_RESPONSE);
    bad.questions[0].correctOptionIds = ["not-an-option-id"];
    expect(() => parseRegeneratedQuiz(JSON.stringify(bad))).toThrow(HttpsError);
  });

  test("rejects a response with no questions array", () => {
    expect(() => parseRegeneratedQuiz(JSON.stringify({ notQuestions: [] }))).toThrow(HttpsError);
  });

  test("unparsable JSON throws rather than silently returning garbage", () => {
    expect(() => parseRegeneratedQuiz("not json at all")).toThrow(HttpsError);
  });
});

describe("runRegenerateQuiz", () => {
  test("wires a scripted model response through end to end, and reports real token usage", async () => {
    const fake = new FakeModelClient(VALID_RESPONSE);
    const { questions, usage } = await runRegenerateQuiz("Photosynthesis turns light into sugar.", fake);
    expect(questions).toHaveLength(1);
    expect(usage.inputTokens).toBeGreaterThan(0);
    expect(usage.outputTokens).toBeGreaterThan(0);
  });
});
