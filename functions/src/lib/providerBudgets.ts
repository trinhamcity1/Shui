import { FieldValue, Transaction } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { db } from "./admin";
import { fetchGolpoCreditsCents } from "./golpo";

/**
 * Resend (resend.com) — a plain HTTPS POST, no SDK needed, matching this
 * codebase's existing convention for third-party APIs (GolpoRestClient).
 * Requires the shareholder to: sign up, verify `shuillc.com` as a sending
 * domain (a couple of DNS records, the same DNS panel used for the site's
 * own A record), create an API key, and set it as this secret. Until then
 * `sendAdminEmailAlert` safely no-ops and logs instead of throwing — a
 * missing email provider must never break lesson generation.
 */
export const resendApiKey = defineSecret("RESEND_API_KEY");
const alertEmailTo = defineString("ALERT_EMAIL_TO", { default: "uyennguyen@shuillc.com" });
const alertEmailFrom = defineString("ALERT_EMAIL_FROM", { default: "Shui Alerts <alerts@shuillc.com>" });

/** Every function that can trigger a low-balance alert needs this in its own `secrets: [...]` list — see createOnDemandLesson.ts and aiTutorMessage.ts. */
export const ALERT_SECRETS = [resendApiKey];

/**
 * **GolpoAI** has a real `GET /users/credits` balance endpoint after all
 * (video.golpoai.com/api-docs/endpoints/v2, confirmed 2026-10 — missed by
 * the original research against their docs, 2026-09) — `getGolpoRemainingCentsLive`
 * below reads it directly and caches the result in Firestore for
 * `GOLPO_CREDITS_CACHE_TTL_MS`, so neither an admin's manual bookkeeping nor
 * `recordProviderSpend` is load-bearing for Golpo anymore; the cache just
 * avoids hitting GolpoAI's API on every single lesson request.
 *
 * **Anthropic** has no equivalent — its API only exposes historical
 * usage/cost over a date range (the Usage & Cost Admin API), never a
 * current balance, and even that requires a separate Admin API key with
 * broader scope than the regular key this app already uses to call Claude.
 * So Anthropic still self-tracks: an admin records what was actually
 * topped up (`recordProviderTopUp`); every real spend gets recorded here at
 * the moment it happens (`recordProviderSpend`, priced via
 * pricing.ts's callCostNanodollars). `recordProviderTopUp`/`recordProviderSpend`
 * both refuse `"golpo"` now — see their own comments.
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
 * Real send via Resend, best-effort — never throws, since a failed alert
 * email must never break lesson generation or an AI tutor reply (both call
 * this indirectly through recordProviderSpend). The Firestore adminAlerts
 * doc (written by the caller alongside this) is the durable record either
 * way; this is a convenience on top of it. `provider` never appears in the
 * email body — Shui never names its render/model vendors to anyone,
 * including in an admin-only alert, so a support person forwarding this
 * email doesn't leak them either.
 */
async function sendAdminEmailAlert(provider: ProviderId, remaining: number, thresholdCents: number): Promise<void> {
  const apiKey = resendApiKey.value();
  const label = provider === "golpo" ? "Video generation" : "AI tutor";
  const subject = remaining <= 0 ? `[Shui] ${label} budget is exhausted` : `[Shui] ${label} budget is low`;
  const body =
    `${label} budget: $${(remaining / 100).toFixed(2)} remaining ` +
    `(alert threshold $${(thresholdCents / 100).toFixed(2)}).\n\n` +
    `Top up on the provider's own dashboard, then record it in Shui's admin console ` +
    `(Creator -> Admin -> Provider budgets) so tracking stays accurate.`;

  if (!apiKey) {
    console.warn(`[providerBudgets] ${subject} — no RESEND_API_KEY configured, email not sent. ${body}`);
    return;
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ from: alertEmailFrom.value(), to: [alertEmailTo.value()], subject, text: body }),
    });
    if (!res.ok) {
      console.error(`[providerBudgets] Resend send failed: ${res.status} ${await res.text()}`);
    }
  } catch (err) {
    console.error("[providerBudgets] Resend send threw", err);
  }
}

/**
 * Only writes the durable Firestore alert doc — called from inside a
 * transaction, so it must never do a network call itself (a Firestore
 * transaction can silently retry its whole callback on contention, which
 * would risk sending the same alert email more than once). The actual email
 * send happens once, after the transaction has actually committed — see
 * both callers below.
 */
function writeAlertIfNeeded(t: Transaction, before: ProviderBudget, after: ProviderBudget): boolean {
  const shouldAlert = isBelowThreshold(after) && !before.alertActive;
  if (shouldAlert) {
    const ref = db.collection("adminAlerts").doc();
    t.set(ref, {
      type: isExhausted(after) ? "provider_budget_exhausted" : "provider_budget_low",
      provider: after.provider,
      remainingCents: remainingCents(after),
      thresholdCents: after.lowBalanceThresholdCents,
      createdAt: FieldValue.serverTimestamp(),
      acknowledged: false,
    });
  }
  return shouldAlert;
}

/**
 * Records a real spend the instant it happens — called anywhere an
 * Anthropic call's real token usage is known (priced via pricing.ts's
 * callCostNanodollars). A no-op for a non-positive amount, so callers never
 * need their own guard. Golpo no longer uses this: its real balance already
 * reflects every spend the instant GolpoAI's own API applies it, so a
 * second, self-tracked copy would only drift from reality for no benefit.
 */
export async function recordProviderSpend(provider: ProviderId, costCents: number): Promise<void> {
  if (provider === "golpo") {
    throw new Error("recordProviderSpend(\"golpo\", ...) is obsolete — Golpo's balance is read live from GolpoAI, nothing to record.");
  }
  if (costCents <= 0) return;
  let shouldAlert = false;
  let after: ProviderBudget | undefined;
  await db.runTransaction(async (t) => {
    const before = await readProviderBudget(provider, t);
    after = {
      ...before,
      spentCentsAllTime: before.spentCentsAllTime + costCents,
      alertActive: before.alertActive || isBelowThreshold({ ...before, spentCentsAllTime: before.spentCentsAllTime + costCents }),
    };
    t.set(
      budgetRef(provider),
      { spentCentsAllTime: FieldValue.increment(costCents), alertActive: after.alertActive, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    shouldAlert = writeAlertIfNeeded(t, before, after);
  });
  if (shouldAlert && after) {
    await sendAdminEmailAlert(after.provider, remainingCents(after), after.lowBalanceThresholdCents);
  }
}

/**
 * Admin-recorded top-up — additive, since a real account accumulates
 * multiple top-ups over time. Clears `alertActive` once the resulting
 * balance is back above threshold, so the next time it crosses down a fresh
 * alert fires rather than staying silently suppressed forever. Golpo isn't
 * eligible — there's no admin-maintained ledger to add to anymore, its
 * balance is read live from GolpoAI's own `/users/credits`.
 */
export async function recordProviderTopUp(provider: ProviderId, amountCents: number): Promise<ProviderBudget> {
  if (provider === "golpo") {
    throw new Error("Golpo's balance is read live from GolpoAI now — nothing to record a top-up against.");
  }
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

/** How long a cached GolpoAI balance is trusted before the next read re-fetches it live — fresh enough for the circuit breaker, cheap enough not to call GolpoAI on every single lesson request. */
export const GOLPO_CREDITS_CACHE_TTL_MS = 5 * 60 * 1000;

/**
 * Golpo's live replacement for `readProviderBudget` — fetches
 * `GET /users/credits` from GolpoAI (via `fetchGolpoCreditsCents`) and
 * caches the result on the same `providerBudgets/golpo` doc the old
 * self-tracked ledger used (reusing `lowBalanceThresholdCents`/
 * `alertActive` from that doc — those admin-configured fields are still
 * meaningful, only the "remaining" figure itself changed where it comes
 * from). A stale cache is served as-is; only an expired one triggers a real
 * API call, so this is safe to call on every `checkProvidersAvailable` and
 * every admin-console load without hammering GolpoAI.
 */
export async function getGolpoRemainingCentsLive(): Promise<number> {
  const ref = budgetRef("golpo");
  const snap = await ref.get();
  const data = snap.data();
  const cachedAtMs = (data?.cachedAt as FirebaseFirestore.Timestamp | undefined)?.toMillis() ?? 0;
  const cachedRemainingCents = data?.cachedRemainingCents as number | undefined;

  if (cachedRemainingCents !== undefined && Date.now() - cachedAtMs < GOLPO_CREDITS_CACHE_TTL_MS) {
    return cachedRemainingCents;
  }

  const remaining = await fetchGolpoCreditsCents();
  const thresholdCents = data?.lowBalanceThresholdCents ?? DEFAULT_LOW_BALANCE_THRESHOLD_CENTS;
  const wasAlertActive = data?.alertActive ?? false;
  const nowBelowThreshold = remaining <= thresholdCents;

  await ref.set(
    {
      cachedRemainingCents: remaining,
      cachedAt: FieldValue.serverTimestamp(),
      lowBalanceThresholdCents: thresholdCents,
      alertActive: nowBelowThreshold,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // Same once-per-crossing discipline as writeAlertIfNeeded, just driven by
  // a live-fetched number instead of a transaction's before/after snapshot
  // — there's no concurrent writer to race here, this only changes on a
  // cache-expiry fetch, not on every request.
  if (nowBelowThreshold && !wasAlertActive) {
    await db.collection("adminAlerts").doc().set({
      type: remaining <= 0 ? "provider_budget_exhausted" : "provider_budget_low",
      provider: "golpo",
      remainingCents: remaining,
      thresholdCents,
      createdAt: FieldValue.serverTimestamp(),
      acknowledged: false,
    });
    await sendAdminEmailAlert("golpo", remaining, thresholdCents);
  }

  return remaining;
}

/**
 * The circuit breaker createOnDemandLesson.ts checks before spending
 * anything — "our tools are currently offline" territory. Deliberately a
 * blunt exhausted/not-exhausted check, not a per-request length estimate:
 * this exists for the worst case (an account genuinely empty), not to
 * second-guess whether a specific request's cost fits in what's left.
 */
export async function checkProvidersAvailable(): Promise<{ available: true } | { available: false; exhaustedProvider: ProviderId }> {
  const golpoRemaining = await getGolpoRemainingCentsLive();
  if (golpoRemaining <= 0) {
    return { available: false, exhaustedProvider: "golpo" };
  }
  const anthropicBudget = await readProviderBudget("anthropic");
  if (isExhausted(anthropicBudget)) {
    return { available: false, exhaustedProvider: "anthropic" };
  }
  return { available: true };
}
