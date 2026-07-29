import Foundation

/// User-facing strings that are reused across screens.
///
/// The app is English-only and has no localization layer — see
/// `prompts/README.md`. One-off strings belong inline at their use site; this
/// namespace exists for the handful that genuinely repeat. Do not grow this
/// into a key-value table that shadows a localization system.
enum Strings {
    // Tab bar
    static let learnTab = "Learn"
    static let exploreTab = "Explore"
    static let profileTab = "Profile"

    // Common actions
    static let cancel = "Cancel"
    static let retry = "Retry"
    static let done = "Done"
    static let save = "Save"
}
