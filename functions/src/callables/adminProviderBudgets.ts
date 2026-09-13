import { onCall, HttpsError } from "firebase-functions/v2/https";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { AdminRecordProviderTopUpInputSchema } from "../schemas/callableInputs";
import { db } from "../lib/admin";
import { PROVIDER_IDS, ProviderBudget, readProviderBudget, recordProviderTopUp, remainingCents } from "../lib/providerBudgets";

export interface ProviderBudgetView extends Omit<ProviderBudget, "updatedAt"> {
  remainingCents: number;
  updatedAt: string | null;
}

function toView(budget: ProviderBudget): ProviderBudgetView {
  return { ...budget, remainingCents: remainingCents(budget), updatedAt: budget.updatedAt?.toDate().toISOString() ?? null };
}

/** Admin-only read of both tracked provider budgets — see providerBudgets.ts for what "tracked" means. */
export const adminGetProviderBudgets = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const budgets = await Promise.all(PROVIDER_IDS.map((provider) => readProviderBudget(provider)));

  const alertsSnap = await db.collection("adminAlerts").where("acknowledged", "==", false).orderBy("createdAt", "desc").limit(20).get();

  return {
    budgets: budgets.map(toView),
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

/**
 * Records a real top-up an admin just made on the provider's own dashboard
 * (Golpo, Anthropic console, etc.) — Shui has no way to observe this
 * automatically since neither provider exposes a balance-webhook or a
 * queryable balance endpoint (see providerBudgets.ts).
 */
export const adminRecordProviderTopUp = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const input = parseInput(AdminRecordProviderTopUpInputSchema, request.data);
  if (!PROVIDER_IDS.includes(input.provider)) {
    throw new HttpsError("invalid-argument", `Unknown provider: ${input.provider}`);
  }
  const updated = await recordProviderTopUp(input.provider, input.amountCents);
  return toView(updated);
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
