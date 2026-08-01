import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}`. Named `UserAccount` (not `UserProfile`) to stay
/// distinct from the local SwiftData `UserProfile`, which holds
/// device-local onboarding preferences only — this is the server record.
///
/// `role` is a display mirror of the `request.auth.token.role` custom claim;
/// rules never trust this field, and neither should app code deciding what a
/// user is allowed to do — that decision belongs server-side.
struct UserAccount: Codable, Identifiable, Hashable {
    enum Role: String, Codable {
        case learner, creator, admin
    }

    @DocumentID var id: String?
    var displayName: String
    var handle: String
    var photoURL: String?
    var bio: String?
    var role: Role
    var authProviders: [String]
    var interests: [String]
    var createdAt: Date?
    var lastActiveAt: Date?
    var currentStreak: Int
    var longestStreak: Int
    var totalVideosCompleted: Int
    var totalQuizzesPassed: Int
    var isGuest: Bool
    var isDeleted: Bool
}
