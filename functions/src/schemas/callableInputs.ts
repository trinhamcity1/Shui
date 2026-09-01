import { z } from "zod";

const MAX_VIDEO_BYTES = 500 * 1024 * 1024;
const MAX_THUMBNAIL_BYTES = 5 * 1024 * 1024;

export const CreateVideoUploadInputSchema = z.object({
  topicId: z.string().min(1),
  title: z.string().min(1).max(200),
  description: z.string().max(2000).optional(),
  sizeBytes: z.number().int().positive().max(MAX_VIDEO_BYTES, "video exceeds the 500 MB upload limit"),
  durationSeconds: z.number().positive(),
  aspectRatio: z.number().positive(),
  contentType: z.enum(["video/mp4", "video/quicktime"]),
});
export type CreateVideoUploadInput = z.infer<typeof CreateVideoUploadInputSchema>;

export const FinalizeVideoUploadInputSchema = z.object({
  videoId: z.string().min(1),
  thumbnailR2Key: z.string().min(1).optional(),
  transcript: z.string().max(20000).optional(),
});
export type FinalizeVideoUploadInput = z.infer<typeof FinalizeVideoUploadInputSchema>;

export const CreateThumbnailUploadInputSchema = z.object({
  videoId: z.string().min(1),
  contentType: z.literal("image/jpeg"),
  sizeBytes: z.number().int().positive().max(MAX_THUMBNAIL_BYTES, "thumbnail exceeds the 5 MB upload limit"),
});
export type CreateThumbnailUploadInput = z.infer<typeof CreateThumbnailUploadInputSchema>;

export const QuizAttemptAnswerSchema = z.object({
  questionId: z.string().min(1),
  selectedOptionIds: z.array(z.string().min(1)),
});

export const SubmitQuizAttemptInputSchema = z.object({
  videoId: z.string().min(1),
  answers: z.array(QuizAttemptAnswerSchema),
});
export type SubmitQuizAttemptInput = z.infer<typeof SubmitQuizAttemptInputSchema>;

export const MarkVideoCompletedInputSchema = z.object({
  videoId: z.string().min(1),
  watchedSeconds: z.number().min(0),
});
export type MarkVideoCompletedInput = z.infer<typeof MarkVideoCompletedInputSchema>;

export const ToggleLikeInputSchema = z.object({
  videoId: z.string().min(1),
});
export type ToggleLikeInput = z.infer<typeof ToggleLikeInputSchema>;

export const ToggleSaveInputSchema = z.object({
  videoId: z.string().min(1),
});
export type ToggleSaveInput = z.infer<typeof ToggleSaveInputSchema>;

export const ToggleCommentLikeInputSchema = z.object({
  videoId: z.string().min(1),
  commentId: z.string().min(1),
});
export type ToggleCommentLikeInput = z.infer<typeof ToggleCommentLikeInputSchema>;

export const SetTopicVisibilityInputSchema = z.object({
  topicId: z.string().min(1),
  visibility: z.enum(["public", "private"]),
});
export type SetTopicVisibilityInput = z.infer<typeof SetTopicVisibilityInputSchema>;

export const SetVideoVisibilityInputSchema = z.object({
  videoId: z.string().min(1),
  visibility: z.enum(["public", "private"]),
});
export type SetVideoVisibilityInput = z.infer<typeof SetVideoVisibilityInputSchema>;

export const SoftDeleteTopicInputSchema = z.object({ topicId: z.string().min(1) });
export type SoftDeleteTopicInput = z.infer<typeof SoftDeleteTopicInputSchema>;

export const SoftDeleteVideoInputSchema = z.object({ videoId: z.string().min(1) });
export type SoftDeleteVideoInput = z.infer<typeof SoftDeleteVideoInputSchema>;

export const SoftDeleteCommentInputSchema = z.object({
  videoId: z.string().min(1),
  commentId: z.string().min(1),
});
export type SoftDeleteCommentInput = z.infer<typeof SoftDeleteCommentInputSchema>;

export const ClaimHandleInputSchema = z.object({
  handle: z
    .string()
    .min(3, "handle must be at least 3 characters")
    .max(20, "handle must be at most 20 characters")
    .regex(/^[a-z0-9_]+$/, "handle may only contain lowercase letters, numbers, and underscores"),
});
export type ClaimHandleInput = z.infer<typeof ClaimHandleInputSchema>;

export const AssignRoleInputSchema = z.object({
  uid: z.string().min(1),
  role: z.enum(["learner", "creator", "admin"]),
});
export type AssignRoleInput = z.infer<typeof AssignRoleInputSchema>;

/**
 * Videos are the strictest collection in the schema — every client write is
 * denied by rules, so even a plain reorder or a title edit has to come
 * through a Function. These two cover the topic editor's needs.
 */
export const ReorderTopicVideosInputSchema = z.object({
  topicId: z.string().min(1),
  // The full ordered list, not a (from, to) pair — a drag reorder rewrites
  // every affected row's `order` anyway, and sending the whole intended
  // result makes the write idempotent and immune to the client and server
  // disagreeing about the starting order.
  videoIds: z.array(z.string().min(1)).min(1).max(200),
});
export type ReorderTopicVideosInput = z.infer<typeof ReorderTopicVideosInputSchema>;

export const UpdateVideoMetadataInputSchema = z.object({
  videoId: z.string().min(1),
  title: z.string().min(1).max(200).optional(),
  description: z.string().max(2000).optional(),
  transcript: z.string().max(20000).optional(),
});
export type UpdateVideoMetadataInput = z.infer<typeof UpdateVideoMetadataInputSchema>;

export const CreateTopicCoverUploadInputSchema = z.object({
  topicId: z.string().min(1),
  contentType: z.literal("image/jpeg"),
  sizeBytes: z.number().int().positive().max(MAX_THUMBNAIL_BYTES, "cover image exceeds the 5 MB upload limit"),
});
export type CreateTopicCoverUploadInput = z.infer<typeof CreateTopicCoverUploadInputSchema>;

export const ActionReportInputSchema = z.object({
  reportId: z.string().min(1),
  action: z.enum(["dismiss", "deleteContent"]),
  note: z.string().max(1000).optional(),
});
export type ActionReportInput = z.infer<typeof ActionReportInputSchema>;

/**
 * Categories are seeded, and creators only ever *select* them — creating one
 * is an admin action available in exactly one place (phase-05 §6), which is
 * why this is a callable rather than a client write despite rules already
 * allowing admin writes to `categories`: the slug/sortOrder bookkeeping
 * below shouldn't be re-implemented per client.
 */
export const SaveCategoryInputSchema = z.object({
  categoryId: z.string().min(1).optional(),
  title: z.string().min(2).max(60),
  description: z.string().max(500),
  // Field names mirror the `Category` Swift model and the seed script
  // exactly (`sfSymbol`/`accentHex`, not `symbolName`/`color`) — a mismatch
  // here writes documents the app decodes as nil.
  sfSymbol: z.string().min(1).max(60),
  accentHex: z
    .string()
    .regex(/^[0-9A-Fa-f]{6}$/, "accentHex must be a 6-digit hex value with no leading #"),
  sortOrder: z.number().int().min(0).max(999),
  isActive: z.boolean(),
});
export type SaveCategoryInput = z.infer<typeof SaveCategoryInputSchema>;

export const SuggestQuizQuestionsInputSchema = z.object({
  videoId: z.string().min(1),
  count: z.number().int().min(1).max(5).default(3),
});
export type SuggestQuizQuestionsInput = z.infer<typeof SuggestQuizQuestionsInputSchema>;

export const AiTutorMessageInputSchema = z
  .object({
    videoId: z.string().min(1),
    mode: z.enum(["discuss", "quizMe"]),
    // 2000-char abuse guardrail from prompts/phase-04-ai-tutor.md §3.
    text: z.string().max(2000).optional(),
    isSessionStart: z.boolean(),
  })
  .superRefine((input, ctx) => {
    if (!input.isSessionStart && (!input.text || input.text.trim().length === 0)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "text is required unless isSessionStart is true",
        path: ["text"],
      });
    }
  });
export type AiTutorMessageInput = z.infer<typeof AiTutorMessageInputSchema>;

// ---- Phase 7: lessons on demand ------------------------------------------

export const CreateOnDemandLessonInputSchema = z.object({
  topic: z.string().min(1).max(300),
});
export type CreateOnDemandLessonInput = z.infer<typeof CreateOnDemandLessonInputSchema>;

export const CheckOnDemandLessonStatusInputSchema = z.object({
  videoId: z.string().min(1),
});
export type CheckOnDemandLessonStatusInput = z.infer<typeof CheckOnDemandLessonStatusInputSchema>;

export const ShareLessonToSocialInputSchema = z.object({
  videoId: z.string().min(1),
});
export type ShareLessonToSocialInput = z.infer<typeof ShareLessonToSocialInputSchema>;

/** The raw signed JWS from StoreKit 2's `VerificationResult` — never a client-reported amount or product. */
export const VerifyAndApplyPurchaseInputSchema = z.object({
  signedTransactionInfo: z.string().min(1),
});
export type VerifyAndApplyPurchaseInput = z.infer<typeof VerifyAndApplyPurchaseInputSchema>;
