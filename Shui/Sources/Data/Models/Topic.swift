import FirebaseFirestore
import Foundation

/// Mirrors `topics/{topicId}` — an ordered playlist of videos under one
/// category. `visibility`, `publishedAt`, and the counters are Function-only
/// writes; the repository layer never attempts to set them directly.
struct Topic: Codable, Identifiable, Hashable {
    enum Visibility: String, Codable {
        case `public`, `private`
    }

    @DocumentID var id: String?
    var title: String
    var subtitle: String
    var description: String
    var categoryId: String
    var coverImageURL: String?
    var visibility: Visibility
    var createdBy: String
    var createdByName: String
    var createdAt: Date?
    var updatedAt: Date?
    var publishedAt: Date?
    var videoCount: Int
    var totalDurationSec: Double
    var learnerCount: Int
    var tags: [String]
    var isDeleted: Bool
}
