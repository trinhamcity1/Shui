import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";

/**
 * Maintains video.commentCount and a parent comment's replyCount. Counts only
 * transition on create/soft-delete/undelete — a plain text edit (same
 * isDeleted before and after) must not double-count or decrement.
 */
export const onCommentWritten = onDocumentWritten(
  "videos/{videoId}/comments/{commentId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const beforeExists = before?.exists ?? false;
    const afterExists = after?.exists ?? false;

    const wasCounted = beforeExists && before!.data()!.isDeleted !== true;
    const isCounted = afterExists && after!.data()!.isDeleted !== true;
    if (wasCounted === isCounted) {
      return;
    }

    const delta = isCounted ? 1 : -1;
    const { videoId } = event.params;
    const videoRef = db.collection("videos").doc(videoId);

    await videoRef.update({ commentCount: FieldValue.increment(delta) }).catch(() => {
      // Video may be gone in a data migration; nothing to reconcile against.
    });

    const parentId = (isCounted ? after : before)?.data()?.parentId;
    if (parentId) {
      const parentRef = videoRef.collection("comments").doc(parentId);
      await parentRef.update({ replyCount: FieldValue.increment(delta) }).catch(() => {
        // Parent comment may itself be gone; nothing to reconcile against.
      });
    }
  }
);
