import { CreateOnDemandLessonInputSchema } from "./callableInputs";

const ok = (data: unknown) => CreateOnDemandLessonInputSchema.safeParse(data).success;

describe("CreateOnDemandLessonInputSchema", () => {
  test("describe mode (the default) needs a topic; long briefs up to 5,000 characters are fine", () => {
    expect(ok({ topic: "compound interest" })).toBe(true);
    expect(ok({ mode: "describe", topic: "x".repeat(5000) })).toBe(true);
    expect(ok({ mode: "describe", topic: "x".repeat(5001) })).toBe(false);
    expect(ok({ mode: "describe", topic: "   " })).toBe(false);
    expect(ok({})).toBe(false);
  });

  test("script mode needs a script and a length, since the script's limit depends on the length", () => {
    expect(ok({ mode: "script", script: "Welcome to the team.", duration: "1" })).toBe(true);
    expect(ok({ mode: "script", script: "Welcome to the team." })).toBe(false);
    expect(ok({ mode: "script", duration: "1" })).toBe(false);
    expect(ok({ mode: "script", script: "x".repeat(2101), duration: "2" })).toBe(false);
  });

  test("voice and purpose only accept real values", () => {
    expect(ok({ topic: "t", voice: "male-1", purpose: "team_training" })).toBe(true);
    expect(ok({ topic: "t", voice: "robot" })).toBe(false);
    expect(ok({ topic: "t", purpose: "marketing" })).toBe(false);
  });
});
