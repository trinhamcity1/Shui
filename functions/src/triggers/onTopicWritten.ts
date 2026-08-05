import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";

interface CountedState {
  categoryId: string;
}

/** Countable = what "N topics" on an Explore category card actually means: public and not soft-deleted. */
export function countedState(data: FirebaseFirestore.DocumentData | undefined): CountedState | null {
  if (!data || data.visibility !== "public" || data.isDeleted !== false) return null;
  return { categoryId: data.categoryId };
}

/**
 * Maintains categories/{categoryId}.topicCount — a known gap through Phase 3
 * (flagged then as "correctly Phase 5's job"): nothing previously updated
 * this counter, so every category showed "0 topics" on Explore regardless of
 * real published content.
 *
 * Fires on publish/unpublish, soft delete, and a category re-pick on an
 * already-public topic (decrements the old category, increments the new
 * one) — a plain field edit that changes neither visibility nor category is
 * a no-op, same discipline as `onCommentWritten`'s isDeleted-transition
 * check.
 *
 * Doesn't retroactively fix topics that went public before this trigger
 * existed — Firestore triggers only fire on writes going forward. Any topic
 * published before this deploy needs one more write (e.g. Unpublish then
 * Publish again) to be picked up.
 */
export const onTopicWritten = onDocumentWritten("topics/{topicId}", async (event) => {
  const before = countedState(event.data?.before.data());
  const after = countedState(event.data?.after.data());

  if (before?.categoryId === after?.categoryId) {
    return;
  }

  const batch = db.batch();
  if (before) {
    batch.update(db.collection("categories").doc(before.categoryId), {
      topicCount: FieldValue.increment(-1),
    });
  }
  if (after) {
    batch.update(db.collection("categories").doc(after.categoryId), {
      topicCount: FieldValue.increment(1),
    });
  }
  await batch.commit().catch(() => {
    // A category may be gone (deactivated categories aren't deleted, so
    // this shouldn't normally happen) — nothing to reconcile against.
  });
});
