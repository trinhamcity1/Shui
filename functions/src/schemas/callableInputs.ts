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
