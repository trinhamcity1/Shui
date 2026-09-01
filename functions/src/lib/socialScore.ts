/**
 * Social tab ranking (phase-07-lessons-on-demand.md §6) — "based on
 * reference, not fully random," implemented without any ML ranking infra:
 * a precomputed popularity score per video, decayed by age, combined at
 * query time with the viewer's own interests (affinity-first,
 * popularity-fallback — see the two-pass query shapes this feeds).
 */

/** Points lost per day since publish — small and linear on purpose, "a simple age-decay term," not a tuned formula. */
const AGE_DECAY_PER_DAY = 0.1;

export function computeSocialScore(params: {
  likeCount: number;
  commentCount: number;
  viewCount: number;
  ageInDays: number;
}): number {
  const engagement =
    Math.log1p(Math.max(0, params.likeCount)) * 2 +
    Math.log1p(Math.max(0, params.commentCount)) +
    Math.log1p(Math.max(0, params.viewCount)) * 0.5;
  const decay = Math.max(0, params.ageInDays) * AGE_DECAY_PER_DAY;
  return engagement - decay;
}

export function ageInDays(publishedAt: Date, now: Date = new Date()): number {
  return Math.max(0, (now.getTime() - publishedAt.getTime()) / (1000 * 60 * 60 * 24));
}
