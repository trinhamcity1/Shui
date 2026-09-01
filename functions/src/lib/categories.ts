/** The closed category taxonomy — prompts/phase-01-backend.md §1. Creators pick from this set; nothing extends it at runtime. */
export const CATEGORY_SLUGS = [
  "personal-development",
  "book-summaries",
  "skills",
  "exam-prep",
  "money-finance",
  "career-business",
  "language-communication",
  "science-tech",
  "health-fitness",
  "history-culture",
  "creativity-arts",
] as const;

export type CategorySlug = (typeof CATEGORY_SLUGS)[number];

export function isCategorySlug(value: unknown): value is CategorySlug {
  return typeof value === "string" && (CATEGORY_SLUGS as readonly string[]).includes(value);
}
