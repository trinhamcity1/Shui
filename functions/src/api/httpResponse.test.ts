import { statusForFunctionsErrorCode, apiError } from "./httpResponse";

describe("statusForFunctionsErrorCode", () => {
  test.each([
    ["invalid-argument", 400],
    ["unauthenticated", 401],
    ["permission-denied", 403],
    ["not-found", 404],
    ["failed-precondition", 409],
    ["resource-exhausted", 402],
    ["internal", 500],
    ["unknown" as const, 500],
  ] as const)("%s -> %i", (code, status) => {
    expect(statusForFunctionsErrorCode(code)).toBe(status);
  });
});

describe("apiError", () => {
  test("shapes a {error: {code, message}} body", () => {
    expect(apiError("invalid_argument", "bad topic")).toEqual({
      error: { code: "invalid_argument", message: "bad topic" },
    });
  });
});
