/**
 * Shared with prompts/phase-01-backend.md §1's mastery formula. Watching
 * without answering can never exceed 40% — that ceiling is what makes the
 * profile progress bar mean something.
 */
export interface TopicProgressCounters {
  videosCompleted: number;
  videosTotal: number;
  quizzesAttempted: number;
  quizzesPassed: number;
  correctAnswers: number;
  totalAnswers: number;
}

export function defaultTopicProgressCounters(): TopicProgressCounters {
  return {
    videosCompleted: 0,
    videosTotal: 0,
    quizzesAttempted: 0,
    quizzesPassed: 0,
    correctAnswers: 0,
    totalAnswers: 0,
  };
}

export function computeMasteryPercent(counters: TopicProgressCounters): number {
  const coverage = counters.videosCompleted / Math.max(counters.videosTotal, 1);
  const accuracy = counters.correctAnswers / Math.max(counters.totalAnswers, 1);
  const retention = counters.quizzesPassed / Math.max(counters.quizzesAttempted, 1);
  return Math.round(100 * (0.4 * coverage + 0.35 * accuracy + 0.25 * retention));
}
