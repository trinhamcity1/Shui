import { onCall, HttpsError } from "firebase-functions/v2/https";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { AdminRecordProviderTopUpInputSchema } from "../schemas/callableInputs";
import { db } from "../lib/admin";
import {
  getGolpoRemainingCentsLive,
  PROVIDER_IDS,
  ProviderBudget,
  readProviderBudget,
  recordProviderTopUp,
  remainingCents,
} from "../lib/providerBudgets";

export interface ProviderBudgetView extends Omit<ProviderBudget, "updatedAt"> {
  remainingCents: number;
  updatedAt: string | null;
  /** true for golpo (read live from GolpoAI's own API, cached) — the admin console uses this to hide the now-meaningless "record a top-up" action. */
  isLive: boolean;
}

function toView(budget: ProviderBudget, remaining: number, isLive: boolean): ProviderBudgetView {
  return { ...budget, remainingCents: remaining, isLive, updatedAt: budget.updatedAt?.toDate().toISOString() ?? null };
}

/** Admin-only read of both provider budgets — golpo is fetched live (cached, see providerBudgets.ts), anthropic is still self-tracked. */
export const adminGetProviderBudgets = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const budgets = await Promise.all(
    PROVIDER_IDS.map(async (provider) => {
      const budget = await readProviderBudget(provider);
      const remaining = provider === "golpo" ? await getGolpoRemainingCentsLive() : remainingCents(budget);
      return toView(budget, remaining, provider === "golpo");
    })
  );

  const alertsSnap = await db.collection("adminAlerts").where("acknowledged", "==", false).orderBy("createdAt", "desc").limit(20).get();

  return {
    budgets,
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
 * Records a real top-up an admin just made on Anthropic's console — Golpo no
 * longer goes through this; its balance is read live from GolpoAI's own
 * API (see providerBudgets.ts), so there's nothing to record for it.
 */
export const adminRecordProviderTopUp = onCall(async (request) => {
  requireRole(request, ["admin"]);
  const input = parseInput(AdminRecordProviderTopUpInputSchema, request.data);
  if (!PROVIDER_IDS.includes(input.provider)) {
    throw new HttpsError("invalid-argument", `Unknown provider: ${input.provider}`);
  }
  if (input.provider === "golpo") {
    throw new HttpsError("failed-precondition", "GolpoAI's balance is read live from their API now — there's nothing to record.");
  }
  const updated = await recordProviderTopUp(input.provider, input.amountCents);
  return toView(updated, remainingCents(updated), false);
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
