import * as fs from "fs";
import * as path from "path";
import { defineString } from "firebase-functions/params";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { TierId } from "./tiers";

/**
 * Every user-facing purchase in Shui is Apple In-App Purchase (StoreKit 2) —
 * digital credit/subscription purchases made from inside an iOS app fall
 * under App Store Review Guideline 3.1.1 and must use IAP, not Stripe or any
 * other processor. See prompts/phase-07-lessons-on-demand.md's "Billing
 * mechanics" section for the full architecture this file implements.
 */
export const appleBundleId = defineString("APPLE_BUNDLE_ID", { default: "com.shui.app" });
export const appleEnvironment = defineString("APPLE_ENVIRONMENT", { default: "Sandbox" });
/** Omitted (undefined) in Sandbox — required once APPLE_ENVIRONMENT is "Production". */
export const appleAppId = defineString("APPLE_APP_APPLE_ID", { default: "" });

/**
 * Apple's root CAs, downloaded from https://www.apple.com/certificateauthority/
 * (the "Apple Root Certificates" section) and committed in
 * functions/certs/apple-root-ca/ — they are public certificates, not
 * secrets. The App Store Server Library's own README leaves sourcing these
 * to each integrator ("Specific implementation may vary"); the three
 * currently committed (Apple Root CA - G3, Apple Root CA - G2) were fetched
 * directly from Apple and validated with `openssl x509`, not fabricated —
 * the original 2005 Apple Computer Root Certificate was fetched too but
 * dropped, since it expired 2025-02-10 and is not part of any current
 * signing chain. Re-download if Apple ever rotates/adds a root — there is
 * no automatic refresh here.
 */
const CERT_DIR = path.join(__dirname, "..", "..", "certs", "apple-root-ca");

export function loadRootCertificates(): Buffer[] {
  if (!fs.existsSync(CERT_DIR)) {
    throw new Error(
      `Apple root CA certificates not found at ${CERT_DIR}. Download the .cer files from ` +
        "https://www.apple.com/certificateauthority/ (Apple Root Certificates section) and commit them there."
    );
  }
  return fs
    .readdirSync(CERT_DIR)
    .filter((f) => f.endsWith(".cer"))
    .map((f) => fs.readFileSync(path.join(CERT_DIR, f)));
}

let cachedVerifier: SignedDataVerifier | null = null;

export function getSignedDataVerifier(): SignedDataVerifier {
  if (!cachedVerifier) {
    const env = appleEnvironment.value() === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const appAppleId = env === Environment.PRODUCTION ? Number(appleAppId.value()) : undefined;
    cachedVerifier = new SignedDataVerifier(loadRootCertificates(), true, env, appleBundleId.value(), appAppleId);
  }
  return cachedVerifier;
}

// ---- product ID -> action mapping (pure, unit-tested) --------------------

export const TOPUP_PRODUCT_ID = "com.shui.app.topup.5";
export const TOPUP_AMOUNT_CENTS = 500; // $5 — Apple requires a fixed price per product

export const SUBSCRIPTION_PRODUCT_IDS: Record<Exclude<TierId, "free" | "siltstone">, string> = {
  obsidian: "com.shui.app.tier.obsidian.monthly",
  alabaster: "com.shui.app.tier.alabaster.monthly",
  pyramidion: "com.shui.app.tier.pyramidion.monthly",
};

export type PurchaseAction = { kind: "topup"; amountCents: number } | { kind: "subscription"; tier: TierId };

export function actionForProductId(productId: string): PurchaseAction | null {
  if (productId === TOPUP_PRODUCT_ID) {
    return { kind: "topup", amountCents: TOPUP_AMOUNT_CENTS };
  }
  const tierEntry = (Object.entries(SUBSCRIPTION_PRODUCT_IDS) as [TierId, string][]).find(
    ([, id]) => id === productId
  );
  if (tierEntry) {
    return { kind: "subscription", tier: tierEntry[0] };
  }
  return null;
}
