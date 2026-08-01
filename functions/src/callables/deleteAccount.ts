import { onCall } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { auth, db } from "../lib/admin";
import { requireAuth } from "../lib/auth";

const BATCH_LIMIT = 400;

/**
 * Deletes every document in a subcollection in batches — Admin SDK has no
 * single-call "delete this subcollection" primitive, and a subcollection
 * isn't removed just because its parent document is.
 */
async function deleteSubcollection(ref: FirebaseFirestore.CollectionReference): Promise<void> {
  while (true) {
    const snap = await ref.limit(BATCH_LIMIT).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    if (snap.size < BATCH_LIMIT) return;
  }
}

/**
 * Required by App Review. Order matters: comments are anonymized (not
 * deleted, so replies keep their context) before the user doc itself is
 * scrubbed, and the Auth user is deleted last so a mid-failure retry never
 * leaves an orphaned Auth account with no corresponding Firestore trace.
 */
export const deleteAccount = onCall(async (request) => {
  const uid = requireAuth(request);
  const userRef = db.collection("users").doc(uid);

  const commentsSnap = await db.collectionGroup("comments").where("uid", "==", uid).get();
  const commentBatches: FirebaseFirestore.WriteBatch[] = [];
  for (let i = 0; i < commentsSnap.docs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const doc of commentsSnap.docs.slice(i, i + BATCH_LIMIT)) {
      batch.update(doc.ref, {
        authorName: "Deleted user",
        authorPhotoURL: null,
        authorHandle: null,
      });
    }
    commentBatches.push(batch);
  }
  for (const batch of commentBatches) {
    await batch.commit();
  }

  await deleteSubcollection(userRef.collection("topicProgress"));
  await deleteSubcollection(userRef.collection("videoProgress"));
  await deleteSubcollection(userRef.collection("likes"));
  await deleteSubcollection(userRef.collection("aiUsage"));

  const userSnap = await userRef.get();
  const handle: string | undefined = userSnap.data()?.handle;
  if (handle) {
    await db.collection("handles").doc(handle).delete();
  }

  await userRef.update({
    // Not FieldValue.delete() -- the Swift model's `handle` is a
    // non-optional String, and removing the field outright would break
    // decoding anywhere this document is still read from (e.g. resolving a
    // comment's author). Empty string reads as "no handle" without risking
    // a collision, since claimHandle never allows an empty handle to be
    // claimed.
    displayName: "Deleted user",
    handle: "",
    photoURL: null,
    bio: null,
    interests: [],
    isDeleted: true,
    updatedAt: FieldValue.serverTimestamp(),
  });

  await auth.deleteUser(uid);

  return { deleted: true };
});
