import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({ region: "us-central1" });

export { createVideoUpload } from "./callables/createVideoUpload";
export { finalizeVideoUpload } from "./callables/finalizeVideoUpload";
export { createThumbnailUpload } from "./callables/createThumbnailUpload";
export { saveQuiz } from "./callables/saveQuiz";
export { submitQuizAttempt } from "./callables/submitQuizAttempt";
export { markVideoCompleted } from "./callables/markVideoCompleted";
export { toggleLike } from "./callables/toggleLike";
export { toggleSave } from "./callables/toggleSave";
export { toggleCommentLike } from "./callables/toggleCommentLike";
export { setTopicVisibility, setVideoVisibility } from "./callables/setVisibility";
export { softDeleteTopic, softDeleteVideo, softDeleteComment } from "./callables/softDelete";
export { claimHandle } from "./callables/claimHandle";
export { assignRole } from "./callables/assignRole";
export { deleteAccount } from "./callables/deleteAccount";
export { aiTutorMessage } from "./callables/aiTutorMessage";
export { reorderTopicVideos, updateVideoMetadata } from "./callables/creatorVideo";
export { createTopicCoverUpload } from "./callables/createTopicCoverUpload";
export { actionReport, saveCategory } from "./callables/adminModeration";
export { suggestQuizQuestions } from "./callables/suggestQuizQuestions";
export { createOnDemandLesson } from "./callables/createOnDemandLesson";
export { checkOnDemandLessonStatus } from "./callables/checkOnDemandLessonStatus";
export { shareLessonToSocial } from "./callables/shareLessonToSocial";
export { verifyAndApplyPurchase } from "./callables/verifyAndApplyPurchase";
export { appStoreServerNotifications } from "./webhooks/appStoreServerNotifications";
export { createApiKey } from "./callables/createApiKey";
export { revokeApiKey } from "./callables/revokeApiKey";
export { listApiKeys } from "./callables/listApiKeys";
export { lessonsApi } from "./api/lessonsApi";

export { onCommentWritten } from "./triggers/onCommentWritten";
export { onTopicWritten } from "./triggers/onTopicWritten";
export { onUserCreated } from "./triggers/onUserCreated";
export { cleanupOrphanedUploads } from "./triggers/cleanupOrphanedUploads";
export { flushViewCounts } from "./triggers/flushViewCounts";
export { onVideoEngagementChanged } from "./triggers/onVideoEngagementChanged";
