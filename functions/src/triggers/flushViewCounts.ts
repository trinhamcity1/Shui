import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";

const BATCH_SIZE = 500;
const MAX_BATCHES_PER_RUN = 20;

/** Clients write view events, never counters — this drains them in batches. */
export const flushViewCounts = onSchedule("every 1 hours", async () => {
  for (let i = 0; i < MAX_BATCHES_PER_RUN; i++) {
    const snap = await db.collection("viewEvents").limit(BATCH_SIZE).get();
    if (snap.empty) return;

    const countsByVideoId = new Map<string, number>();
    for (const doc of snap.docs) {
      const videoId = doc.data().videoId as string;
      countsByVideoId.set(videoId, (countsByVideoId.get(videoId) ?? 0) + 1);
    }

    const batch = db.batch();
    for (const [videoId, count] of countsByVideoId) {
      batch.update(db.collection("videos").doc(videoId), { viewCount: FieldValue.increment(count) });
    }
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (snap.size < BATCH_SIZE) return;
  }
});
