import { HttpsError } from "firebase-functions/v2/https";
import { TypeOf, ZodTypeAny } from "zod";

export function parseInput<S extends ZodTypeAny>(schema: S, data: unknown): TypeOf<S> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const message = result.error.issues
      .map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("; ");
    throw new HttpsError("invalid-argument", message);
  }
  return result.data;
}
