import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "./admin";
import { CategorySlug } from "./categories";
import { LessonSpec } from "./lessonSpec";

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

/** Same idea, different length/frame/audience/voice is a different rendered file. */
export function cacheKeyFor(normalizedTopic: string, spec: LessonSpec): string {
  return createHash("sha256")
    .update(`${normalizedTopic}::${spec.duration}::${spec.orientation}::${spec.purpose}::${spec.voice}`)
    .digest("hex");
}

export interface LessonCacheEntry extends LessonSpec {
  canonicalTopic: string;
  sourceVideoId: string;
  categoryId: CategorySlug;
  hitCount: number;
}

export async function lookupLessonCache(rawTopic: string, spec: LessonSpec): Promise<LessonCacheEntry | null> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), spec);
  const snap = await db.collection("lessonCache").doc(key).get();
  if (!snap.exists) return null;
  return snap.data() as LessonCacheEntry;
}

export async function recordLessonCacheHit(rawTopic: string, spec: LessonSpec): Promise<void> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), spec);
  await db.collection("lessonCache").doc(key).update({ hitCount: FieldValue.increment(1) });
}

export async function writeLessonCache(
  rawTopic: string,
  spec: LessonSpec,
  entry: Omit<LessonCacheEntry, "hitCount" | keyof LessonSpec>
): Promise<void> {
  const key = cacheKeyFor(normalizeTopic(rawTopic), spec);
  await db
    .collection("lessonCache")
    .doc(key)
    .set({ ...entry, ...spec, hitCount: 0, createdAt: FieldValue.serverTimestamp() });
}
