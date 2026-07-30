import FirebaseFirestore
import Foundation

/// Mirrors `videos/{videoId}/comments/{commentId}`. One level of threading
/// only — `parentId` is nil for a top-level comment.
struct Comment: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var uid: String
    var authorName: String
    var authorPhotoURL: String?
    var authorHandle: String?
    var text: String
    var createdAt: Date?
    var editedAt: Date?
    var parentId: String?
    var replyCount: Int
    var likeCount: Int
    var isDeleted: Bool
    var reportCount: Int
}
