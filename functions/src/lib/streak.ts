/**
 * Day-boundary streak bump, keyed on UTC calendar day. Same day as the last
 * activity: no change. Exactly the day after: streak continues. Any bigger
 * gap: streak resets to 1 (today counts as day one of a new streak).
 */
export interface StreakState {
  currentStreak: number;
  longestStreak: number;
}

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function nextStreak(
  lastActiveAt: Date | null,
  now: Date,
  currentStreak: number,
  longestStreak: number
): StreakState {
  if (!lastActiveAt) {
    return { currentStreak: 1, longestStreak: Math.max(1, longestStreak) };
  }

  const lastDay = dayKey(lastActiveAt);
  const nowDay = dayKey(now);
  if (lastDay === nowDay) {
    return { currentStreak, longestStreak };
  }

  const yesterday = dayKey(new Date(now.getTime() - 24 * 60 * 60 * 1000));
  const nextCurrent = lastDay === yesterday ? currentStreak + 1 : 1;
  return { currentStreak: nextCurrent, longestStreak: Math.max(longestStreak, nextCurrent) };
}
