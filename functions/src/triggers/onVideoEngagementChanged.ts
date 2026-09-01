import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { ageInDays, computeSocialScore } from "../lib/socialScore";

/**
 * Maintains videos/{videoId}.socialScore (phase-07-lessons-on-demand.md §6)
 * whenever the counters it's derived from change. A reactive trigger here,
 * not an inline recompute inside toggleLike/onCommentWritten/
 * flushViewCounts, because those three are independent writers of
 * likeCount/commentCount/viewCount with no single owning callable to hang
 * the recompute off of — one trigger watching the video doc's own counters
 * is the version of "precompute the aggregate, never live on the client"
 * that actually fits this shape, versus copying the same recompute call
 * into three unrelated places and risking one of them drifting out of sync.
 *
 * Guarded against re-triggering on its own write: it only recomputes when
 * likeCount/commentCount/viewCount actually changed, and its own update
 * touches only socialScore — so the write this function makes never causes
 * another invocation of itself.
 */
export const onVideoEngagementChanged = onDocumentUpdated("videos/{videoId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const engagementChanged =
    before.likeCount !== after.likeCount || before.commentCount !== after.commentCount || before.viewCount !== after.viewCount;
  if (!engagementChanged) return;

  const publishedAt: Date = after.publishedAt?.toDate?.() ?? new Date();
  const newScore = computeSocialScore({
    likeCount: after.likeCount ?? 0,
    commentCount: after.commentCount ?? 0,
    viewCount: after.viewCount ?? 0,
    ageInDays: ageInDays(publishedAt),
  });

  if (after.socialScore === newScore) return;

  await event.data!.after.ref.update({ socialScore: newScore });
});
