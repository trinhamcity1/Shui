import { FieldValue, Transaction } from "firebase-admin/firestore";
import { db } from "./admin";

/**
 * Self-tracked spend against Shui's own GolpoAI and Anthropic accounts —
 * "self-tracked" because neither provider exposes a live "remaining
 * balance" API (confirmed against GolpoAI's own docs, 2026-09; Anthropic's
 * account-level balance isn't a single queryable number either). An admin
 * records what was actually topped up (`recordProviderTopUp`); every real
 * spend gets recorded here at the moment it happens
 * (`recordProviderSpend`), priced with the same per-minute/per-token rates
 * Shui already uses elsewhere (GOLPO_CENTS_PER_MINUTE, pricing.ts). The
 * difference is the tracked "remaining" figure admins and the app's own
 * circuit breaker (createOnDemandLesson.ts) act on.
 */
export type ProviderId = "golpo" | "anthropic";

export const PROVIDER_IDS: ProviderId[] = ["golpo", "anthropic"];

/** $50 default — the threshold the shareholder asked for; adjustable per provider via recordProviderTopUp's companion admin callable. */
export const DEFAULT_LOW_BALANCE_THRESHOLD_CENTS = 5000;

export interface ProviderBudget {
  provider: ProviderId;
  toppedUpCentsAllTime: number;
  spentCentsAllTime: number;
  lowBalanceThresholdCents: number;
  /** True from the moment remaining balance first crosses the threshold until a top-up clears it — prevents re-alerting on every single subsequent spend. */
  alertActive: boolean;
  updatedAt: FirebaseFirestore.Timestamp | null;
}

function budgetRef(provider: ProviderId) {
  return db.collection("providerBudgets").doc(provider);
}

function budgetFromSnap(provider: ProviderId, data: FirebaseFirestore.DocumentData | undefined): ProviderBudget {
  return {
    provider,
    toppedUpCentsAllTime: data?.toppedUpCentsAllTime ?? 0,
    spentCentsAllTime: data?.spentCentsAllTime ?? 0,
    lowBalanceThresholdCents: data?.lowBalanceThresholdCents ?? DEFAULT_LOW_BALANCE_THRESHOLD_CENTS,
    alertActive: data?.alertActive ?? false,
    updatedAt: data?.updatedAt ?? null,
  };
}

export async function readProviderBudget(provider: ProviderId, t?: Transaction): Promise<ProviderBudget> {
  const ref = budgetRef(provider);
  const snap = t ? await t.get(ref) : await ref.get();
  return budgetFromSnap(provider, snap.data());
}

export function remainingCents(budget: ProviderBudget): number {
  return budget.toppedUpCentsAllTime - budget.spentCentsAllTime;
}

export function isExhausted(budget: ProviderBudget): boolean {
  return remainingCents(budget) <= 0;
}

export function isBelowThreshold(budget: ProviderBudget): boolean {
  return remainingCents(budget) <= budget.lowBalanceThresholdCents;
}

/**
 * Not a real email/push send yet — no transactional email provider is
 * configured (checked: nothing in this codebase sends email today). Logs so
 * the alert is never silently lost, and the Firestore adminAlerts doc
 * (written by the caller alongside this) is what actually surfaces the
 * alert today, in the admin console. Wiring a real provider later is a
 * change to this one function only — every call site stays the same.
 */
function sendAdminEmailAlert(provider: ProviderId, remaining: number, thresholdCents: number): void {
  console.warn(
    `[providerBudgets] ${provider} balance low: $${(remaining / 100).toFixed(2)} remaining ` +
      `(threshold $${(thresholdCents / 100).toFixed(2)}). No email provider configured — ` +
      `surfaced in the admin console only. See providerBudgets.ts's sendAdminEmailAlert.`
  );
}

async function writeAlertIfNeeded(t: Transaction, before: ProviderBudget, after: ProviderBudget): Promise<void> {
  const nowBelow = isBelowThreshold(after);
  if (nowBelow && !before.alertActive) {
    const ref = db.collection("adminAlerts").doc();
    t.set(ref, {
      type: isExhausted(after) ? "provider_budget_exhausted" : "provider_budget_low",
      provider: after.provider,
      remainingCents: remainingCents(after),
      thresholdCents: after.lowBalanceThresholdCents,
      createdAt: FieldValue.serverTimestamp(),
      acknowledged: false,
    });
    sendAdminEmailAlert(after.provider, remainingCents(after), after.lowBalanceThresholdCents);
  }
}

/**
 * Records a real spend the instant it happens — called from
 * createOnDemandLesson.ts (Golpo, priced at GOLPO_CENTS_PER_MINUTE) and
 * anywhere an Anthropic call's real token usage is known (priced via
 * pricing.ts's callCostNanodollars). A no-op for a non-positive amount, so
 * callers never need their own guard.
 */
export async function recordProviderSpend(provider: ProviderId, costCents: number): Promise<void> {
  if (costCents <= 0) return;
  await db.runTransaction(async (t) => {
    const before = await readProviderBudget(provider, t);
    const after: ProviderBudget = {
      ...before,
      spentCentsAllTime: before.spentCentsAllTime + costCents,
      alertActive: before.alertActive || isBelowThreshold({ ...before, spentCentsAllTime: before.spentCentsAllTime + costCents }),
    };
    t.set(
      budgetRef(provider),
      { spentCentsAllTime: FieldValue.increment(costCents), alertActive: after.alertActive, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    await writeAlertIfNeeded(t, before, after);
  });
}

/**
 * Admin-recorded top-up — additive, since a real account accumulates
 * multiple top-ups over time. Clears `alertActive` once the resulting
 * balance is back above threshold, so the next time it crosses down a fresh
 * alert fires rather than staying silently suppressed forever.
 */
export async function recordProviderTopUp(provider: ProviderId, amountCents: number): Promise<ProviderBudget> {
  return db.runTransaction(async (t) => {
    const before = await readProviderBudget(provider, t);
    const after: ProviderBudget = {
      ...before,
      toppedUpCentsAllTime: before.toppedUpCentsAllTime + amountCents,
      alertActive: before.alertActive && isBelowThreshold({ ...before, toppedUpCentsAllTime: before.toppedUpCentsAllTime + amountCents }),
    };
    t.set(
      budgetRef(provider),
      { toppedUpCentsAllTime: FieldValue.increment(amountCents), alertActive: after.alertActive, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return after;
  });
}

export async function setProviderThreshold(provider: ProviderId, thresholdCents: number): Promise<void> {
  await budgetRef(provider).set({ lowBalanceThresholdCents: thresholdCents, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

/**
 * The circuit breaker createOnDemandLesson.ts checks before spending
 * anything — "our tools are currently offline" territory. Deliberately a
 * blunt exhausted/not-exhausted check, not a per-request length estimate:
 * this exists for the worst case (an account genuinely empty), not to
 * second-guess whether a specific request's cost fits in what's left.
 */
export async function checkProvidersAvailable(): Promise<{ available: true } | { available: false; exhaustedProvider: ProviderId }> {
  for (const provider of PROVIDER_IDS) {
    const budget = await readProviderBudget(provider);
    if (isExhausted(budget)) {
      return { available: false, exhaustedProvider: provider };
    }
  }
  return { available: true };
}
