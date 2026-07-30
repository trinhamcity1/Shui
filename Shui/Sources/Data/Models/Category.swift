import FirebaseFirestore
import Foundation

/// Mirrors `categories/{categoryId}` — the fixed taxonomy creators pick a
/// topic's category from. Seeded once; only an admin claim can write it.
struct Category: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var title: String
    var slug: String
    var description: String
    var sfSymbol: String
    var accentHex: String
    var sortOrder: Int
    var topicCount: Int
    var isActive: Bool
}
