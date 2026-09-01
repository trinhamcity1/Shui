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
    // Optional because `topics/personal-{uid}` (phase-07 — every learner's
    // on-demand-lesson container, `ensurePersonalTopic`) is written with
    // `categoryId: null`: it holds lessons across every category, not one.
    var categoryId: String?
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
    /// `true` only for a learner's own `personal-{uid}` on-demand topic —
    /// excluded from every public topic listing (Explore, search) the same
    /// way `isDeleted` is, just for a different reason.
    var isPersonal: Bool? = nil
}

extension Topic {
    /// Mirrors `personalTopicId(uid)` in
    /// `functions/src/lib/onDemandVideo.ts` exactly — both sides compute the
    /// same deterministic id independently rather than one telling the
    /// other, since the client needs it to query `videos` before it has any
    /// document (the topic, or a lesson) to read it back from.
    static func personalTopicId(uid: String) -> String { "personal-\(uid)" }
}
