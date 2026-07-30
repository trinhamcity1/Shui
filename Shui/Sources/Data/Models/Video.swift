import FirebaseFirestore
import Foundation

/// Mirrors `videos/{videoId}` — top-level, not a subcollection of `topics`,
/// because the feed queries across topics. `r2Key` deliberately isn't
/// modeled here: the client only ever needs `playbackURL`.
///
/// A video is only servable to a learner when `status == .ready`,
/// `visibility == .public`, `topicVisibility == .public`, and
/// `isDeleted == false` — see `videoIsPublic` in firestore.rules, which is
/// the authoritative version of this check.
struct Video: Codable, Identifiable, Hashable {
    enum Visibility: String, Codable {
        case `public`, `private`
    }

    enum Status: String, Codable {
        case pending, uploading, ready, failed
    }

    @DocumentID var id: String?
    var topicId: String
    var topicTitle: String
    var categoryId: String
    var topicVisibility: Visibility
    var title: String
    var description: String
    var order: Int
    var playbackURL: String
    var thumbnailURL: String?
    var durationSeconds: Double
    var aspectRatio: Double
    var sizeBytes: Int
    var transcript: String?
    var visibility: Visibility
    var status: Status
    var statusMessage: String?
    var createdBy: String
    var createdAt: Date?
    var updatedAt: Date?
    var publishedAt: Date?
    var hasQuiz: Bool
    var likeCount: Int
    var commentCount: Int
    var viewCount: Int
    var completionCount: Int
    var isDeleted: Bool
}
