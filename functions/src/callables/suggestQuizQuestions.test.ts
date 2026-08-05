import { parseSuggestions } from "./suggestQuizQuestions";

const validQuestion = {
  prompt: "What does the legislative branch do?",
  options: [
    { text: "Writes laws", isCorrect: true },
    { text: "Interprets laws", isCorrect: false },
    { text: "Enforces laws", isCorrect: false },
  ],
  explanation: "Congress writes the laws; the other two branches interpret and enforce them.",
};

function wrap(questions: unknown[]): string {
  return JSON.stringify({ questions });
}

describe("parseSuggestions", () => {
  it("parses a well-formed draft", () => {
    const result = parseSuggestions(wrap([validQuestion]), 3);
    expect(result).toHaveLength(1);
    expect(result[0]?.prompt).toBe(validQuestion.prompt);
    expect(result[0]?.options.filter((o) => o.isCorrect)).toHaveLength(1);
  });

  it("strips a markdown fence the model added despite being told not to", () => {
    const fenced = "```json\n" + wrap([validQuestion]) + "\n```";
    expect(parseSuggestions(fenced, 3)).toHaveLength(1);
  });

  it("caps the result at the requested count", () => {
    const result = parseSuggestions(wrap([validQuestion, validQuestion, validQuestion]), 2);
    expect(result).toHaveLength(2);
  });

  it("drops a question with fewer than 2 options rather than returning an unsavable draft", () => {
    const tooFew = { ...validQuestion, options: [{ text: "Only one", isCorrect: true }] };
    expect(() => parseSuggestions(wrap([tooFew]), 3)).toThrow();
  });

  it("drops a question with more than 6 options", () => {
    const tooMany = {
      ...validQuestion,
      options: Array.from({ length: 7 }, (_, i) => ({ text: `Option ${i}`, isCorrect: i === 0 })),
    };
    expect(() => parseSuggestions(wrap([tooMany]), 3)).toThrow();
  });

  it("drops a question with no correct option marked", () => {
    const noneCorrect = {
      ...validQuestion,
      options: validQuestion.options.map((o) => ({ ...o, isCorrect: false })),
    };
    expect(() => parseSuggestions(wrap([noneCorrect]), 3)).toThrow();
  });

  it("drops a question with more than one correct option", () => {
    const twoCorrect = {
      ...validQuestion,
      options: validQuestion.options.map((o) => ({ ...o, isCorrect: true })),
    };
    expect(() => parseSuggestions(wrap([twoCorrect]), 3)).toThrow();
  });

  it("keeps the good questions when only some are unusable", () => {
    const broken = { ...validQuestion, options: [{ text: "Only one", isCorrect: true }] };
    const result = parseSuggestions(wrap([broken, validQuestion]), 3);
    expect(result).toHaveLength(1);
    expect(result[0]?.prompt).toBe(validQuestion.prompt);
  });

  it("throws on unparseable JSON rather than returning junk", () => {
    expect(() => parseSuggestions("not json at all", 3)).toThrow();
  });

  it("throws on a well-formed but empty question list", () => {
    expect(() => parseSuggestions(wrap([]), 3)).toThrow();
  });

  it("skips entries missing a prompt or explanation", () => {
    const noExplanation = { prompt: "Q?", options: validQuestion.options };
    expect(() => parseSuggestions(wrap([noExplanation]), 3)).toThrow();
  });
});
