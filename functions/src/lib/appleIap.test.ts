import { X509Certificate } from "crypto";
import {
  actionForProductId,
  loadRootCertificates,
  SUBSCRIPTION_PRODUCT_IDS,
  TOPUP_AMOUNT_CENTS,
  TOPUP_PRODUCT_ID,
} from "./appleIap";

describe("actionForProductId", () => {
  test("the top-up consumable maps to a $5 topup action", () => {
    expect(actionForProductId(TOPUP_PRODUCT_ID)).toEqual({ kind: "topup", amountCents: TOPUP_AMOUNT_CENTS });
  });

  test("each subscription product maps to its own tier", () => {
    expect(actionForProductId(SUBSCRIPTION_PRODUCT_IDS.obsidian)).toEqual({ kind: "subscription", tier: "obsidian" });
    expect(actionForProductId(SUBSCRIPTION_PRODUCT_IDS.alabaster)).toEqual({ kind: "subscription", tier: "alabaster" });
    expect(actionForProductId(SUBSCRIPTION_PRODUCT_IDS.pyramidion)).toEqual({
      kind: "subscription",
      tier: "pyramidion",
    });
  });

  test("an unknown product id maps to nothing, not a guess", () => {
    expect(actionForProductId("com.shui.app.something.unrecognized")).toBeNull();
  });
});

describe("loadRootCertificates", () => {
  test("loads real, currently-valid Apple root certificates from disk, not placeholders", () => {
    const certs = loadRootCertificates();
    expect(certs.length).toBeGreaterThan(0);
    for (const der of certs) {
      const cert = new X509Certificate(der);
      expect(cert.issuer).toMatch(/Apple/);
      expect(new Date(cert.validTo).getTime()).toBeGreaterThan(Date.now());
    }
  });
});
