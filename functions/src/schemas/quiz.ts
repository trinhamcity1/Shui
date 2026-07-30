import { z } from "zod";

/**
 * Validates a quiz exactly as prompts/phase-01-backend.md §1 specifies:
 * 1–5 questions, 2–6 options per question, at least one correct option,
 * every correctOptionIds entry present in options, non-empty prompts and
 * explanations. saveQuiz rejects with these messages rather than storing a
 * malformed quiz — a broken quiz in the feed is worse than a missing one.
 */

export const QuizOptionSchema = z.object({
  id: z.string().min(1, "option id must not be empty"),
  text: z.string().min(1, "option text must not be empty"),
});

export const QuizQuestionInputSchema = z
  .object({
    id: z.string().min(1, "question id must not be empty"),
    prompt: z.string().min(1, "prompt must not be empty"),
    options: z
      .array(QuizOptionSchema)
      .min(2, "each question needs at least 2 options")
      .max(6, "each question allows at most 6 options"),
    correctOptionIds: z
      .array(z.string().min(1))
      .min(1, "each question needs at least one correct option"),
    requiredCorrectCount: z.number().int().min(1),
    explanation: z.string().min(1, "explanation must not be empty"),
    orderIndex: z.number().int().min(0),
  })
  .superRefine((question, ctx) => {
    const optionIds = new Set(question.options.map((o) => o.id));
    const duplicateOptionIds = question.options
      .map((o) => o.id)
      .filter((id, i, arr) => arr.indexOf(id) !== i);
    if (duplicateOptionIds.length > 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `duplicate option id(s): ${[...new Set(duplicateOptionIds)].join(", ")}`,
        path: ["options"],
      });
    }
    for (const correctId of question.correctOptionIds) {
      if (!optionIds.has(correctId)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `correctOptionIds entry "${correctId}" is not present in options`,
          path: ["correctOptionIds"],
        });
      }
    }
    if (question.requiredCorrectCount > question.correctOptionIds.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "requiredCorrectCount exceeds the number of correct options",
        path: ["requiredCorrectCount"],
      });
    }
  });

export const QuizInputSchema = z.object({
  videoId: z.string().min(1),
  questions: z
    .array(QuizQuestionInputSchema)
    .min(1, "a quiz needs at least 1 question")
    .max(5, "a quiz allows at most 5 questions"),
  passThreshold: z.number().min(0).max(1).default(0.6),
});

export type QuizInput = z.infer<typeof QuizInputSchema>;
export type QuizQuestionInput = z.infer<typeof QuizQuestionInputSchema>;

/**
 * The public-readable half of a saved quiz — prompts and options only. This
 * is what videos/{videoId}/quiz/current stores and what quiz rules allow
 * anyone with video visibility to read.
 */
export interface StoredQuizCurrent {
  version: number;
  questions: Array<{
    id: string;
    prompt: string;
    options: Array<{ id: string; text: string }>;
    requiredCorrectCount: number;
    orderIndex: number;
  }>;
  passThreshold: number;
  updatedBy: string;
  updatedAt: FirebaseFirestore.FieldValue | Date;
}

/**
 * The owner-only half — correctOptionIds and explanation. Stored at
 * videos/{videoId}/quiz/answers, read only by submitQuizAttempt and by the
 * video's own owner/admin (rules), never by a learner directly.
 */
export interface StoredQuizAnswers {
  version: number;
  answers: Array<{
    id: string;
    correctOptionIds: string[];
    explanation: string;
  }>;
}

export function splitQuizForStorage(
  input: QuizInput,
  version: number,
  updatedBy: string,
  updatedAt: FirebaseFirestore.FieldValue
): { current: StoredQuizCurrent; answers: StoredQuizAnswers } {
  return {
    current: {
      version,
      passThreshold: input.passThreshold,
      updatedBy,
      updatedAt,
      questions: input.questions.map((q) => ({
        id: q.id,
        prompt: q.prompt,
        options: q.options,
        requiredCorrectCount: q.requiredCorrectCount,
        orderIndex: q.orderIndex,
      })),
    },
    answers: {
      version,
      answers: input.questions.map((q) => ({
        id: q.id,
        correctOptionIds: q.correctOptionIds,
        explanation: q.explanation,
      })),
    },
  };
}
