import * as fs from "fs";
import * as path from "path";
import { defineString } from "firebase-functions/params";
import { Environment, SignedDataVerifier, VerificationException, VerificationStatus } from "@apple/app-store-server-library";
import { TierId } from "./tiers";

/**
 * Every user-facing purchase in Shui is Apple In-App Purchase (StoreKit 2) —
 * digital credit/subscription purchases made from inside an iOS app fall
 * under App Store Review Guideline 3.1.1 and must use IAP, not Stripe or any
 * other processor. See prompts/phase-07-lessons-on-demand.md's "Billing
 * mechanics" section for the full architecture this file implements.
 */
export const appleBundleId = defineString("APPLE_BUNDLE_ID", { default: "com.shui.app" });
/** Only "Xcode" changes anything (local StoreKit Testing) — see verifierEnvironments. */
export const appleEnvironment = defineString("APPLE_ENVIRONMENT", { default: "Sandbox" });
/**
 * The numeric Apple ID from App Store Connect → App Information. Apple
 * requires it to verify Production purchases, so until it's set only
 * Sandbox purchases verify.
 */
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

/**
 * "Xcode" lets `APPLE_ENVIRONMENT` be pointed at local StoreKit Testing
 * (Simulator, `Shui/Shui.storekit`, no App Store Connect products or sandbox
 * tester account needed) — Apple signs those transactions with `environment:
 * "Xcode"` in the JWS payload, and `SignedDataVerifier` rejects a transaction
 * whose environment doesn't exactly match how it was constructed (see
 * `jws_verification.js`'s `decodedJWT.environment !== this.environment`
 * check). Without this, every local-StoreKit-Testing purchase would fail
 * verification even though the on-device purchase itself succeeded. Never
 * set this in a deployed/production project — it's for a developer's own
 * `.secrets.local.env`-style local override while testing against Simulator.
 */
export function resolveAppleEnvironment(value: string): Environment {
  if (value === "Production") return Environment.PRODUCTION;
  if (value === "Xcode") return Environment.XCODE;
  return Environment.SANDBOX;
}

/**
 * Every environment a real purchase can come from, most likely first.
 * App Review and TestFlight buy in Apple's *sandbox* even on the release
 * build, while customers buy in *production* — and a SignedDataVerifier
 * accepts exactly one environment, rejecting the other's payloads as
 * INVALID_ENVIRONMENT. Apple's guidance is for one server to accept both
 * (otherwise either the reviewer's test purchase fails, or every real
 * one does). "Xcode" pins local StoreKit Testing to its own environment.
 */
export function verifierEnvironments(configured: string, appAppleId: string): Environment[] {
  if (resolveAppleEnvironment(configured) === Environment.XCODE) return [Environment.XCODE];
  return appAppleId ? [Environment.PRODUCTION, Environment.SANDBOX] : [Environment.SANDBOX];
}

let cachedVerifiers: SignedDataVerifier[] | null = null;

function getVerifiers(): SignedDataVerifier[] {
  if (!cachedVerifiers) {
    const certificates = loadRootCertificates();
    const appAppleId = appleAppId.value();
    cachedVerifiers = verifierEnvironments(appleEnvironment.value(), appAppleId).map(
      (env) =>
        new SignedDataVerifier(
          certificates,
          true,
          env,
          appleBundleId.value(),
          env === Environment.PRODUCTION ? Number(appAppleId) : undefined
        )
    );
  }
  return cachedVerifiers;
}

/**
 * Tries each environment in turn, moving on only when one rejects the
 * payload for coming from a different environment. Any other failure — a
 * bad signature, another app's purchase — is final.
 */
async function verifyInAnyEnvironment<T>(verify: (verifier: SignedDataVerifier) => Promise<T>): Promise<T> {
  const verifiers = getVerifiers();
  let lastError: unknown = new Error("No App Store verifier is configured.");
  for (const verifier of verifiers) {
    try {
      return await verify(verifier);
    } catch (error) {
      lastError = error;
      const wrongEnvironment = error instanceof VerificationException && error.status === VerificationStatus.INVALID_ENVIRONMENT;
      if (!wrongEnvironment) throw error;
    }
  }
  throw lastError;
}

export function verifyTransaction(signedTransactionInfo: string) {
  return verifyInAnyEnvironment((verifier) => verifier.verifyAndDecodeTransaction(signedTransactionInfo));
}

export function verifyNotification(signedPayload: string) {
  return verifyInAnyEnvironment((verifier) => verifier.verifyAndDecodeNotification(signedPayload));
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
