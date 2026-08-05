import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}/savedVideos/{videoId}` — a private bookmark, not a
/// public engagement signal like a like. Denormalized the same way
/// `LikedVideo` is, so the "Saved videos" grid is a single query with no
/// fan-out reads.
struct SavedVideo: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var videoId: String
    var topicId: String
    var videoTitle: String
    var thumbnailURL: String?
    var savedAt: Date?
}
