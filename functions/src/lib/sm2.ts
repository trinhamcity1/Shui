/**
 * Server-side port of Shui/Sources/Learning/SpacedRepetitionScheduler.swift.
 *
 * This must agree with the Swift implementation — submitQuizAttempt grades
 * and reschedules server-side, but the iOS app needs the identical math to
 * reason about due dates and (eventually) show a review queue without a
 * round trip for every card. sm2.test.ts asserts the same behavior the
 * Swift test suite does; when either changes, change both and re-check.
 */

export type ReviewGrade = "again" | "hard" | "good" | "easy";

const GRADE_QUALITY: Record<ReviewGrade, number> = {
  again: 0,
  hard: 3,
  good: 4,
  easy: 5,
};

export const DEFAULT_EASE_FACTOR = 2.5;
export const MINIMUM_EASE_FACTOR = 1.3;

export interface ReviewState {
  easeFactor: number;
  intervalDays: number;
  repetitions: number;
  dueDate: Date;
  lastReviewedAt: Date | null;
}

/** A never-reviewed item. Due immediately — see ReviewState.new in Swift. */
export function newReviewState(now: Date = new Date()): ReviewState {
  return {
    easeFactor: DEFAULT_EASE_FACTOR,
    intervalDays: 0,
    repetitions: 0,
    dueDate: now,
    lastReviewedAt: null,
  };
}

export function isNew(state: ReviewState): boolean {
  return state.repetitions === 0 && state.lastReviewedAt === null;
}

export function isDue(state: ReviewState, now: Date = new Date()): boolean {
  return state.dueDate.getTime() <= now.getTime();
}

/** Pure — returns a new ReviewState rather than mutating the input. */
export function schedule(
  state: ReviewState,
  grade: ReviewGrade,
  now: Date = new Date()
): ReviewState {
  const quality = GRADE_QUALITY[grade];
  let intervalDays: number;
  let repetitions: number;

  if (grade === "again") {
    repetitions = 0;
    intervalDays = 1;
  } else {
    switch (state.repetitions) {
      case 0:
        intervalDays = 1;
        break;
      case 1:
        intervalDays = 6;
        break;
      default:
        intervalDays = Math.round(state.intervalDays * state.easeFactor);
        break;
    }
    repetitions = state.repetitions + 1;
  }

  const easeDelta = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02);
  const easeFactor = Math.max(MINIMUM_EASE_FACTOR, state.easeFactor + easeDelta);

  const dueDate = addDays(now, Math.max(intervalDays, 1));

  return { easeFactor, intervalDays, repetitions, dueDate, lastReviewedAt: now };
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date.getTime());
  result.setDate(result.getDate() + days);
  return result;
}
