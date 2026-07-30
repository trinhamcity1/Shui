import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

export function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return request.auth.uid;
}

export function requireNotGuest(request: CallableRequest): string {
  const uid = requireAuth(request);
  if (request.auth?.token.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("permission-denied", "A full account is required for this action.");
  }
  return uid;
}

export function requireRole(request: CallableRequest, roles: string[]): string {
  const uid = requireAuth(request);
  const role = request.auth?.token.role as string | undefined;
  if (!role || !roles.includes(role)) {
    throw new HttpsError("permission-denied", `Requires role: ${roles.join(" or ")}.`);
  }
  return uid;
}

export function isAdminRequest(request: CallableRequest): boolean {
  return request.auth?.token.role === "admin";
}
