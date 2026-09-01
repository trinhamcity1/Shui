import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "./admin";
import { CategorySlug } from "./categories";
import { GolpoTiming } from "./tiers";

/**
 * v1 scope is exact-normalized-string matching only (phase-07 §5) —
 * semantic near-duplicate matching is a deliberate later decision, not
 * pretended here. Lowercase, trim, collapse whitespace, strip punctuation.
 */
export function normalizeTopic(raw: string): string {
  return raw
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ");
}

export function cacheKeyFor(normalizedTopic: string, timing: GolpoTiming): string {
  return createHash("sha256").update(`${normalizedTopic}::${timing}`).digest("hex");
}

export interface LessonCacheEntry {
  canonicalTopic: string;
  sourceVideoId: string;
  categoryId: CategorySlug;
  timing: GolpoTiming;
  hitCount: number;
}

export async function lookupLessonCache(rawTopic: string, timing: GolpoTiming): Promise<LessonCacheEntry | null> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), timing);
  const snap = await db.collection("lessonCache").doc(key).get();
  if (!snap.exists) return null;
  return snap.data() as LessonCacheEntry;
}

export async function recordLessonCacheHit(rawTopic: string, timing: GolpoTiming): Promise<void> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), timing);
  await db.collection("lessonCache").doc(key).update({ hitCount: FieldValue.increment(1) });
}

export async function writeLessonCache(
  rawTopic: string,
  timing: GolpoTiming,
  entry: Omit<LessonCacheEntry, "hitCount">
): Promise<void> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), timing);
  await db
    .collection("lessonCache")
    .doc(key)
    .set({ ...entry, hitCount: 0, createdAt: FieldValue.serverTimestamp() });
}
