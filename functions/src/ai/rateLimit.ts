import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";

/** prompts/phase-04-ai-tutor.md §3's example numbers. */
export const HOURLY_LIMIT = 30;
export const DAILY_LIMIT = 300;

export interface RateLimitResult {
  allowed: boolean;
  hourlyUsed: number;
  dailyUsed: number;
  /** Only meaningful when `allowed` is false — when the cap clears. */
  resetAt: Date;
}

/**
 * Checks and, if allowed, atomically records one message against both caps
 * in a single document write — `users/{uid}/aiUsage/{yyyy-mm-dd}` (UTC day),
 * with a 24-slot hour bucket inside it so one doc covers both the hourly and
 * daily limit without a second collection.
 */
export async function checkAndRecordUsage(uid: string, now: Date = new Date()): Promise<RateLimitResult> {
  const dayKey = now.toISOString().slice(0, 10);
  const hour = now.getUTCHours();
  const ref = db.collection("users").doc(uid).collection("aiUsage").doc(dayKey);

  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const data = snap.exists ? (snap.data() as { count?: number; hourCounts?: number[] }) : {};
    const hourCounts = data.hourCounts ?? new Array(24).fill(0);
    const dailyUsed = data.count ?? 0;
    const hourlyUsed = hourCounts[hour] ?? 0;

    if (hourlyUsed >= HOURLY_LIMIT) {
      const resetAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hour + 1, 0, 0));
      return { allowed: false, hourlyUsed, dailyUsed, resetAt };
    }
    if (dailyUsed >= DAILY_LIMIT) {
      const resetAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 0, 0, 0));
      return { allowed: false, hourlyUsed, dailyUsed, resetAt };
    }

    const nextHourCounts = [...hourCounts];
    nextHourCounts[hour] = hourlyUsed + 1;
    t.set(
      ref,
      { count: dailyUsed + 1, hourCounts: nextHourCounts, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { allowed: true, hourlyUsed: hourlyUsed + 1, dailyUsed: dailyUsed + 1, resetAt: now };
  });
}
