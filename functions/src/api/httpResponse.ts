import { FunctionsErrorCode } from "firebase-functions/v2/https";

/**
 * `lessonsApi` (the developer-facing REST surface) has no Callable-SDK
 * client to decode a `functions/*` error code back into something
 * meaningful — it has to pick a real HTTP status itself. Kept pure and
 * separate from the request handler so the mapping is unit-testable without
 * standing up an HTTP request.
 */
export function statusForFunctionsErrorCode(code: FunctionsErrorCode): number {
  switch (code) {
    case "invalid-argument":
      return 400;
    case "unauthenticated":
      return 401;
    case "permission-denied":
      return 403;
    case "not-found":
      return 404;
    case "failed-precondition":
    case "already-exists":
    case "aborted":
      return 409;
    case "resource-exhausted":
      // Insufficient credit, not a rate limit (that's a plain 429 raised
      // before this mapping is ever reached) — 402 is the closest standard
      // status for "this needs more of the account's balance."
      return 402;
    default:
      return 500;
  }
}

export interface ApiErrorBody {
  error: { code: string; message: string };
}

export function apiError(code: string, message: string): ApiErrorBody {
  return { error: { code, message } };
}
