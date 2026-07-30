import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { deleteObject, R2_SECRETS } from "../lib/r2";

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

/**
 * Never hard-deletes a video document — only the R2 object it points at.
 * `r2CleanedUpAt` is internal bookkeeping so a video doesn't get re-swept
 * (and re-billed against the R2 API) every day forever once it's cleaned.
 */
export const cleanupOrphanedUploads = onSchedule(
  { schedule: "every 24 hours", secrets: R2_SECRETS },
  async () => {
    const now = Date.now();

    const staleUploadingSnap = await db.collection("videos").where("status", "==", "uploading").get();
    await Promise.all(
      staleUploadingSnap.docs.map(async (doc) => {
        const updatedAt = (doc.data().updatedAt as Timestamp | undefined)?.toMillis() ?? 0;
        if (now - updatedAt > TWENTY_FOUR_HOURS_MS) {
          await doc.ref.update({
            status: "failed",
            statusMessage: "Upload timed out before it was finalized.",
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      })
    );

    const [failedSnap, deletedSnap] = await Promise.all([
      db.collection("videos").where("status", "==", "failed").get(),
      db.collection("videos").where("isDeleted", "==", true).get(),
    ]);
    const candidates = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    for (const doc of [...failedSnap.docs, ...deletedSnap.docs]) {
      candidates.set(doc.id, doc);
    }

    await Promise.all(
      [...candidates.values()].map(async (doc) => {
        const data = doc.data();
        if (data.r2CleanedUpAt) return;
        const updatedAt = (data.updatedAt as Timestamp | undefined)?.toMillis() ?? 0;
        if (now - updatedAt <= SEVEN_DAYS_MS) return;

        if (data.r2Key) {
          await deleteObject(data.r2Key).catch(() => {
            // Already gone from R2; nothing to reconcile.
          });
        }
        await doc.ref.update({ r2CleanedUpAt: FieldValue.serverTimestamp() });
      })
    );
  }
);
