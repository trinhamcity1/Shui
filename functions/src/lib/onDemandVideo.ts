import { FieldValue } from "firebase-admin/firestore";
import { db } from "./admin";
import { CategorySlug } from "./categories";

export function personalTopicId(uid: string): string {
  return `personal-${uid}`;
}

/**
 * Idempotent — safe to call on every lesson request, same discipline
 * seed_civics.ts uses for its own idempotent writes. isPersonal: true is
 * the explicit filter every public topic listing must exclude on, rather
 * than relying on categoryId == null being remembered everywhere.
 */
export async function ensurePersonalTopic(uid: string): Promise<string> {
  const topicId = personalTopicId(uid);
  await db.collection("topics").doc(topicId).set(
    {
      title: "My Lessons",
      subtitle: "Generated just for you",
      description: "",
      categoryId: null,
      isPersonal: true,
      visibility: "private",
      createdBy: uid,
      createdByName: "",
      videoCount: 0,
      totalDurationSec: 0,
      learnerCount: 0,
      tags: [],
      isDeleted: false,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return topicId;
}

export function truncateTitle(topic: string): string {
  const trimmed = topic.trim();
  return trimmed.length > 80 ? `${trimmed.slice(0, 77)}...` : trimmed;
}

/**
 * The shared shell every on-demand video doc starts from — both the cache-hit
 * path and the full-generation path in createOnDemandLesson build on this,
 * so the two never drift apart on the fields that don't differ between them.
 */
export function baseOnDemandVideoShape(params: {
  uid: string;
  topicId: string;
  categoryId: CategorySlug;
  title: string;
}) {
  return {
    topicId: params.topicId,
    topicTitle: "My Lessons",
    categoryId: params.categoryId,
    topicVisibility: "private" as const,
    title: params.title,
    description: "",
    order: 0,
    r2Key: null,
    thumbnailURL: null,
    aspectRatio: 9 / 16,
    visibility: "private" as const,
    statusMessage: null,
    createdBy: params.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    publishedAt: null,
    likeCount: 0,
    commentCount: 0,
    viewCount: 0,
    completionCount: 0,
    isDeleted: false,
    sharedToSocial: false,
    sharedAt: null,
    refundClaimed: false,
  };
}
