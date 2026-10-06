import { onCall, HttpsError } from "firebase-functions/v2/https";
import { requireRole } from "../lib/auth";
import { db } from "../lib/admin";
import { DEFAULT_LOW_BALANCE_THRESHOLD_CENTS, getGolpoRemainingCentsLive } from "../lib/providerBudgets";

export interface ProviderBudgetView {
  provider: "golpo";
  remainingCents: number;
  lowBalanceThresholdCents: number;
  alertActive: boolean;
  updatedAt: string | null;
}

/** Admin-only read of GolpoAI's balance — fetched live (cached a few minutes, see providerBudgets.ts). */
export const adminGetProviderBudgets = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const remaining = await getGolpoRemainingCentsLive();
  const snap = await db.collection("providerBudgets").doc("golpo").get();
  const data = snap.data();

  const budget: ProviderBudgetView = {
    provider: "golpo",
    remainingCents: remaining,
    lowBalanceThresholdCents: data?.lowBalanceThresholdCents ?? DEFAULT_LOW_BALANCE_THRESHOLD_CENTS,
    alertActive: data?.alertActive ?? false,
    updatedAt: (data?.updatedAt as FirebaseFirestore.Timestamp | undefined)?.toDate().toISOString() ?? null,
  };

  const alertsSnap = await db.collection("adminAlerts").where("acknowledged", "==", false).orderBy("createdAt", "desc").limit(20).get();

  return {
    budgets: [budget],
    openAlerts: alertsSnap.docs.map((doc) => {
      const data = doc.data();
      return {
        alertId: doc.id,
        type: data.type as string,
        provider: data.provider as string,
        remainingCents: data.remainingCents as number,
        thresholdCents: data.thresholdCents as number,
        createdAt: (data.createdAt as FirebaseFirestore.Timestamp | undefined)?.toDate().toISOString() ?? null,
      };
    }),
  };
});

/** Marks an alert as seen — doesn't affect whether a future crossing re-alerts, that's governed by `alertActive` on the budget doc itself. */
export const adminAcknowledgeAlert = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const alertId = (request.data as { alertId?: unknown } | undefined)?.alertId;
  if (typeof alertId !== "string" || !alertId) {
    throw new HttpsError("invalid-argument", "alertId is required.");
  }
  await db.collection("adminAlerts").doc(alertId).set({ acknowledged: true }, { merge: true });
  return { acknowledged: true };
});
