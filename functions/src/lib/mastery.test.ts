import { computeMasteryPercent, defaultTopicProgressCounters } from "./mastery";

describe("computeMasteryPercent", () => {
  test("a topic with no activity has zero mastery", () => {
    expect(computeMasteryPercent(defaultTopicProgressCounters())).toBe(0);
  });

  test("watching without answering can never exceed 40%", () => {
    const percent = computeMasteryPercent({
      videosCompleted: 10,
      videosTotal: 10,
      quizzesAttempted: 0,
      quizzesPassed: 0,
      correctAnswers: 0,
      totalAnswers: 0,
    });
    expect(percent).toBeLessThanOrEqual(40);
  });

  test("full coverage, accuracy, and retention gives 100", () => {
    const percent = computeMasteryPercent({
      videosCompleted: 5,
      videosTotal: 5,
      quizzesAttempted: 5,
      quizzesPassed: 5,
      correctAnswers: 20,
      totalAnswers: 20,
    });
    expect(percent).toBe(100);
  });

  test("matches the documented formula for a mixed case", () => {
    // coverage = 0.5, accuracy = 0.75, retention = 0.5
    // 100 * (0.4*0.5 + 0.35*0.75 + 0.25*0.5) = 100 * (0.2 + 0.2625 + 0.125) = 58.75 -> rounds to 59
    const percent = computeMasteryPercent({
      videosCompleted: 5,
      videosTotal: 10,
      quizzesAttempted: 4,
      quizzesPassed: 2,
      correctAnswers: 3,
      totalAnswers: 4,
    });
    expect(percent).toBe(59);
  });
});
