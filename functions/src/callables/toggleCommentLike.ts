import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireNotGuest } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ToggleCommentLikeInputSchema } from "../schemas/callableInputs";

/// Mirrors toggleLike's video pattern, scoped to a comment instead — a
/// separate callable rather than a generalized "like anything" one, since
/// the two write to different documents (a comment isn't a video) and rules
/// already treat them as distinct collections.
export const toggleCommentLike = onCall(async (request) => {
  const uid = requireNotGuest(request);
  const input = parseInput(ToggleCommentLikeInputSchema, request.data);

  const commentRef = db.collection("videos").doc(input.videoId).collection("comments").doc(input.commentId);
  const likeRef = db.collection("users").doc(uid).collection("commentLikes").doc(input.commentId);

  const liked = await db.runTransaction(async (t) => {
    const [commentSnap, likeSnap] = await Promise.all([t.get(commentRef), t.get(likeRef)]);
    if (!commentSnap.exists) {
      throw new HttpsError("not-found", "Comment not found.");
    }

    if (likeSnap.exists) {
      t.delete(likeRef);
      t.update(commentRef, { likeCount: FieldValue.increment(-1) });
      return false;
    }

    t.set(likeRef, { videoId: input.videoId, commentId: input.commentId, likedAt: FieldValue.serverTimestamp() });
    t.update(commentRef, { likeCount: FieldValue.increment(1) });
    return true;
  });

  return { liked };
});
