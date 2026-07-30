import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}/likes/{videoId}` — denormalized so the "Liked
/// videos" grid is a single query with no fan-out reads.
struct LikedVideo: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var videoId: String
    var topicId: String
    var videoTitle: String
    var thumbnailURL: String?
    var likedAt: Date?
}
