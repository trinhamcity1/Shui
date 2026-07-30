import { isDue, isNew, MINIMUM_EASE_FACTOR, newReviewState, schedule } from "./sm2";

describe("sm2", () => {
  test("failing resets interval and repetitions", () => {
    const state = { ...newReviewState(), repetitions: 3, intervalDays: 10 };
    const next = schedule(state, "again");
    expect(next.repetitions).toBe(0);
    expect(next.intervalDays).toBe(1);
  });

  test("passing grows interval across repetitions", () => {
    const now = new Date();
    let state = newReviewState(now);

    state = schedule(state, "good", now);
    expect(state.repetitions).toBe(1);
    expect(state.intervalDays).toBe(1);

    state = schedule(state, "good", now);
    expect(state.repetitions).toBe(2);
    expect(state.intervalDays).toBe(6);

    const intervalBefore = state.intervalDays;
    state = schedule(state, "good", now);
    expect(state.repetitions).toBe(3);
    expect(state.intervalDays).toBeGreaterThan(intervalBefore);
  });

  test("ease factor never drops below minimum", () => {
    let state = newReviewState();
    for (let i = 0; i < 25; i++) {
      state = schedule(state, "again");
    }
    expect(state.easeFactor).toBeGreaterThanOrEqual(MINIMUM_EASE_FACTOR);
  });

  test("isDue respects dueDate", () => {
    const now = new Date();
    let state = newReviewState(now);

    state = { ...state, dueDate: new Date(now.getTime() + 3600_000) };
    expect(isDue(state, now)).toBe(false);

    state = { ...state, dueDate: new Date(now.getTime() - 3600_000) };
    expect(isDue(state, now)).toBe(true);
  });

  test("new state is immediately due", () => {
    const now = new Date();
    const state = newReviewState(now);
    expect(isNew(state)).toBe(true);
    expect(isDue(state, now)).toBe(true);
  });

  test("schedule does not mutate the input state", () => {
    const original = newReviewState();
    const snapshot = { ...original };
    schedule(original, "good");
    expect(original).toEqual(snapshot);
  });

  test("agrees with the Swift ReviewState default ease factor", () => {
    // Both implementations must start from the same constant, or a video
    // graded identically on iOS and by the server would diverge from the
    // first review onward.
    expect(newReviewState().easeFactor).toBe(2.5);
  });
});
