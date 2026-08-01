import FirebaseAnalytics

/// The one place outside `FirebaseBootstrap.swift` allowed to import
/// FirebaseAnalytics, so the rest of the app can log events without
/// importing Firebase itself.
///
/// A small, deliberate event set — enough to answer "are people learning?",
/// not a firehose (`prompts/phase-03-discovery-social.md` §8). No PII in any
/// parameter — ids only, never names/emails/handles.
enum AppAnalytics {
    static func logVideoLoadFailed(videoId: String) {
        Analytics.logEvent("video_load_failed", parameters: ["video_id": videoId])
    }

    static func logVideoStarted(videoId: String, topicId: String, categoryId: String) {
        Analytics.logEvent("video_started", parameters: [
            "video_id": videoId, "topic_id": topicId, "category_id": categoryId,
        ])
    }

    static func logVideoCompleted(videoId: String, topicId: String, categoryId: String) {
        Analytics.logEvent("video_completed", parameters: [
            "video_id": videoId, "topic_id": topicId, "category_id": categoryId,
        ])
    }

    static func logQuizSubmitted(videoId: String, score: Double, passed: Bool) {
        Analytics.logEvent("quiz_submitted", parameters: [
            "video_id": videoId, "score": score, "passed": passed,
        ])
    }

    static func logQuizSkipped(videoId: String) {
        Analytics.logEvent("quiz_skipped", parameters: ["video_id": videoId])
    }

    static func logTopicStarted(topicId: String, categoryId: String) {
        Analytics.logEvent("topic_started", parameters: ["topic_id": topicId, "category_id": categoryId])
    }

    static func logInterestsSelected(count: Int) {
        Analytics.logEvent("interest_selected", parameters: ["count": count])
    }

    static func logSignInCompleted(method: String) {
        Analytics.logEvent("sign_in_completed", parameters: ["method": method])
    }

    static func logCommentPosted(videoId: String, isReply: Bool) {
        Analytics.logEvent("comment_posted", parameters: ["video_id": videoId, "is_reply": isReply])
    }

    static func logAIOpened(videoId: String) {
        Analytics.logEvent("ai_opened", parameters: ["video_id": videoId])
    }
}
