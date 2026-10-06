import { FieldValue } from "firebase-admin/firestore";
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

/** `createOnDemandLesson.ts` needs this in its own `secrets: [...]` list — it's the only function that can still trigger a low-balance alert. */
export const ALERT_SECRETS = [resendApiKey];

/**
 * GolpoAI's own spend tracking — read live, not self-tracked. Their real v2
 * API has a `GET /users/credits` balance endpoint (video.golpoai.com/api-
 * docs/endpoints/v2, confirmed 2026-10 — missed by the original research
 * against their docs in 2026-09, which is why this used to be an
 * admin-maintained ledger). `getGolpoRemainingCentsLive` below calls it with
 * the same `GOLPO_API_KEY` already used for rendering, and caches the
 * result in Firestore for `GOLPO_CREDITS_CACHE_TTL_MS` so the circuit
 * breaker isn't hitting GolpoAI's API on every single lesson request.
 *
 * Anthropic spend is deliberately not tracked here at all — their API only
 * exposes historical usage/cost over a date range, never a current balance,
 * and even that needs a separate Admin API key this project doesn't have.
 * Anthropic's own account-level spending limit and email alerts (set
 * directly in their console) are the safety net for that provider instead.
 */
const GOLPO_DOC = db.collection("providerBudgets").doc("golpo");

/** $50 default — the threshold the shareholder asked for. */
export const DEFAULT_LOW_BALANCE_THRESHOLD_CENTS = 5000;

/** How long a cached GolpoAI balance is trusted before the next read re-fetches it live. */
export const GOLPO_CREDITS_CACHE_TTL_MS = 5 * 60 * 1000;

/**
 * Real send via Resend, best-effort — never throws, since a failed alert
 * email must never break lesson generation. The Firestore `adminAlerts` doc
 * (written by the caller alongside this) is the durable record either way;
 * this is a convenience on top of it.
 */
async function sendAdminEmailAlert(remaining: number, thresholdCents: number): Promise<void> {
  const apiKey = resendApiKey.value();
  const subject = remaining <= 0 ? "[Shui] Video generation budget is exhausted" : "[Shui] Video generation budget is low";
  const body =
    `Video generation budget: $${(remaining / 100).toFixed(2)} remaining ` +
    `(alert threshold $${(thresholdCents / 100).toFixed(2)}).\n\n` +
    `Top up on the provider's own dashboard — Shui reads the new balance automatically within a few minutes.`;

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
 * Fetches `GET /users/credits` from GolpoAI and caches the result on
 * `providerBudgets/golpo` (reusing `lowBalanceThresholdCents`/`alertActive`
 * from that doc — those admin-configured fields are still meaningful, only
 * the "remaining" figure itself changed where it comes from). A fresh cache
 * is served as-is; only an expired one triggers a real API call, so this is
 * safe to call on every `checkProvidersAvailable` and every admin-console
 * load without hammering GolpoAI.
 */
export async function getGolpoRemainingCentsLive(): Promise<number> {
  const snap = await GOLPO_DOC.get();
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

  await GOLPO_DOC.set(
    {
      cachedRemainingCents: remaining,
      cachedAt: FieldValue.serverTimestamp(),
      lowBalanceThresholdCents: thresholdCents,
      alertActive: nowBelowThreshold,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // Once-per-crossing: only fires the moment remaining first drops to/below
  // threshold, not on every subsequent cache refresh while it stays low.
  if (nowBelowThreshold && !wasAlertActive) {
    await db.collection("adminAlerts").doc().set({
      type: remaining <= 0 ? "provider_budget_exhausted" : "provider_budget_low",
      provider: "golpo",
      remainingCents: remaining,
      thresholdCents,
      createdAt: FieldValue.serverTimestamp(),
      acknowledged: false,
    });
    await sendAdminEmailAlert(remaining, thresholdCents);
  }

  return remaining;
}

/**
 * The circuit breaker createOnDemandLesson.ts checks before spending
 * anything — "our tools are currently offline" territory.
 */
export async function checkProvidersAvailable(): Promise<{ available: true } | { available: false }> {
  const remaining = await getGolpoRemainingCentsLive();
  return remaining > 0 ? { available: true } : { available: false };
}
