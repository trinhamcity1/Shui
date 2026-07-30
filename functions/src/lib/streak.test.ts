import { nextStreak } from "./streak";

describe("nextStreak", () => {
  test("first ever activity starts a streak of 1", () => {
    const result = nextStreak(null, new Date("2026-07-30T12:00:00Z"), 0, 0);
    expect(result).toEqual({ currentStreak: 1, longestStreak: 1 });
  });

  test("activity again on the same UTC day does not change the streak", () => {
    const result = nextStreak(
      new Date("2026-07-30T01:00:00Z"),
      new Date("2026-07-30T23:00:00Z"),
      3,
      5
    );
    expect(result).toEqual({ currentStreak: 3, longestStreak: 5 });
  });

  test("activity on the very next UTC day extends the streak", () => {
    const result = nextStreak(
      new Date("2026-07-29T23:30:00Z"),
      new Date("2026-07-30T00:30:00Z"),
      3,
      5
    );
    expect(result).toEqual({ currentStreak: 4, longestStreak: 5 });
  });

  test("a gap of more than one day resets the streak to 1", () => {
    const result = nextStreak(
      new Date("2026-07-20T12:00:00Z"),
      new Date("2026-07-30T12:00:00Z"),
      10,
      15
    );
    expect(result).toEqual({ currentStreak: 1, longestStreak: 15 });
  });

  test("longestStreak grows when the current streak surpasses it", () => {
    const result = nextStreak(
      new Date("2026-07-29T12:00:00Z"),
      new Date("2026-07-30T12:00:00Z"),
      5,
      5
    );
    expect(result).toEqual({ currentStreak: 6, longestStreak: 6 });
  });
});
