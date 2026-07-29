import Foundation
import SwiftData

/// Device-local preferences only.
///
/// Identity, progress, streaks, and role live in Firebase — `users/{uid}` and
/// its subcollections. Nothing here is synced, and nothing here is
/// authoritative about the learner. The point of keeping it local is that
/// launch never blocks on a network call to decide whether to show onboarding.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var hasCompletedOnboarding: Bool = false
    /// Category ids selected at onboarding. Mirrored to `users/{uid}.interests`
    /// once signed in; kept locally so the first feed can be ordered before any
    /// round trip completes.
    var selectedInterests: [String] = []
    /// Last topic the learner opened, for the "Continue" affordance.
    var lastOpenedTopicID: String?
    var createdAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.hasCompletedOnboarding = false
        self.selectedInterests = []
        self.lastOpenedTopicID = nil
        self.createdAt = createdAt
    }
}
