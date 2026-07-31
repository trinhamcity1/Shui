import FirebaseAnalytics

/// The one place outside `FirebaseBootstrap.swift` allowed to import
/// FirebaseAnalytics, so the rest of the app can log events without
/// importing Firebase itself.
enum AppAnalytics {
    static func logVideoLoadFailed(videoId: String) {
        Analytics.logEvent("video_load_failed", parameters: ["video_id": videoId])
    }
}
