import { QuizInputSchema, splitQuizForStorage } from "./quiz";

function validQuestion(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: "q1",
    prompt: "What is the supreme law of the land?",
    options: [
      { id: "a", text: "The Constitution" },
      { id: "b", text: "The Declaration of Independence" },
    ],
    correctOptionIds: ["a"],
    requiredCorrectCount: 1,
    explanation: "The Constitution is the supreme law of the land.",
    orderIndex: 0,
    ...overrides,
  };
}

describe("QuizInputSchema", () => {
  test("accepts a well-formed quiz", () => {
    const result = QuizInputSchema.safeParse({ videoId: "v1", questions: [validQuestion()] });
    expect(result.success).toBe(true);
  });

  test("defaults passThreshold to 0.6 when omitted", () => {
    const result = QuizInputSchema.parse({ videoId: "v1", questions: [validQuestion()] });
    expect(result.passThreshold).toBe(0.6);
  });

  test("rejects a duplicate option id", () => {
    const result = QuizInputSchema.safeParse({
      videoId: "v1",
      questions: [validQuestion({ options: [{ id: "a", text: "X" }, { id: "a", text: "Y" }] })],
    });
    expect(result.success).toBe(false);
  });

  test("rejects a correctOptionIds entry not present in options", () => {
    const result = QuizInputSchema.safeParse({
      videoId: "v1",
      questions: [validQuestion({ correctOptionIds: ["not-an-option"] })],
    });
    expect(result.success).toBe(false);
  });

  test("rejects requiredCorrectCount exceeding the number of correct options", () => {
    const result = QuizInputSchema.safeParse({
      videoId: "v1",
      questions: [validQuestion({ requiredCorrectCount: 2, correctOptionIds: ["a"] })],
    });
    expect(result.success).toBe(false);
  });

  test("rejects fewer than 2 options", () => {
    const result = QuizInputSchema.safeParse({
      videoId: "v1",
      questions: [validQuestion({ options: [{ id: "a", text: "Only one" }] })],
    });
    expect(result.success).toBe(false);
  });

  test("rejects more than 5 questions", () => {
    const questions = Array.from({ length: 6 }, (_, i) => validQuestion({ id: `q${i}` }));
    const result = QuizInputSchema.safeParse({ videoId: "v1", questions });
    expect(result.success).toBe(false);
  });

  test("rejects zero questions", () => {
    const result = QuizInputSchema.safeParse({ videoId: "v1", questions: [] });
    expect(result.success).toBe(false);
  });
});

describe("splitQuizForStorage", () => {
  test("keeps prompts and options in current, correctness only in answers", () => {
    const input = QuizInputSchema.parse({ videoId: "v1", questions: [validQuestion()] });
    const { current, answers } = splitQuizForStorage(input, 1, "owner1", new Date() as never);

    expect(current.questions[0]).not.toHaveProperty("correctOptionIds");
    expect(current.questions[0]).not.toHaveProperty("explanation");
    expect(current.questions[0]!.options).toEqual(input.questions[0]!.options);

    expect(answers.answers[0]!.correctOptionIds).toEqual(["a"]);
    expect(answers.answers[0]!.explanation).toBe(input.questions[0]!.explanation);
    expect(current.version).toBe(1);
    expect(answers.version).toBe(1);
  });
});
