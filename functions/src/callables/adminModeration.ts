import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireRole } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { ActionReportInputSchema, SaveCategoryInputSchema } from "../schemas/callableInputs";

/**
 * Rules deny every client update to `reports`, so clearing the queue runs
 * here. Both actions write the same audit trail (`actionedBy`/`actionedAt`)
 * — a dismissal is a moderation decision worth being able to review later,
 * not a no-op.
 */
export const actionReport = onCall(async (request) => {
  const uid = requireRole(request, ["admin"]);
  const input = parseInput(ActionReportInputSchema, request.data);
  const reportRef = db.collection("reports").doc(input.reportId);

  const reportSnap = await reportRef.get();
  if (!reportSnap.exists) {
    throw new HttpsError("not-found", "Report not found.");
  }
  const report = reportSnap.data()!;

  if (input.action === "deleteContent") {
    const targetPath = report.targetPath as string | undefined;
    if (!targetPath) {
      throw new HttpsError("failed-precondition", "This report has no target to delete.");
    }
    // Soft delete, like every other delete in this codebase — the reported
    // comment stays readable to moderators and keeps its replies threaded,
    // exactly as `softDeleteComment` does when an author removes their own.
    const targetRef = db.doc(targetPath);
    const targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "The reported content no longer exists.");
    }
    await targetRef.update({
      isDeleted: true,
      deletedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  await reportRef.update({
    status: input.action === "dismiss" ? "dismissed" : "actioned",
    actionNote: input.note ?? null,
    actionedBy: uid,
    actionedAt: FieldValue.serverTimestamp(),
  });

  return { status: input.action === "dismiss" ? "dismissed" : "actioned" };
});

/**
 * Creating a category is deliberately available in exactly one place in the
 * product (admin surface, phase-05 §6) — creators only ever select from the
 * seeded list. Categories are deactivated via `isActive`, never deleted, so
 * there's no delete counterpart here.
 */
export const saveCategory = onCall(async (request) => {
  const uid = requireRole(request, ["admin"]);
  const input = parseInput(SaveCategoryInputSchema, request.data);

  const base = {
    title: input.title,
    description: input.description,
    symbolName: input.symbolName,
    sortOrder: input.sortOrder,
    isActive: input.isActive,
    updatedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (input.categoryId) {
    const ref = db.collection("categories").doc(input.categoryId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Category not found.");
    }
    await ref.update(base);
    return { categoryId: input.categoryId, created: false };
  }

  // Slug from the title so category IDs stay human-readable in the console
  // and in `topics.categoryId`, matching how the seed script names them.
  const slug = input.title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (!slug) {
    throw new HttpsError("invalid-argument", "Category title must contain at least one letter or number.");
  }

  const ref = db.collection("categories").doc(slug);
  const existing = await ref.get();
  if (existing.exists) {
    throw new HttpsError("already-exists", `A category with the id "${slug}" already exists.`);
  }

  await ref.set({
    ...base,
    topicCount: 0,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { categoryId: slug, created: true };
});
