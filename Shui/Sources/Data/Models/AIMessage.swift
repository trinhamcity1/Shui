import FirebaseFirestore
import Foundation

/// The mode toggle at the top of `AITutorSheet` — matches the string values
/// `aiTutorMessage` expects and stores (`mode` on `AiTutorMessageInput` and
/// on every persisted message), not just a display concept.
enum AIThreadMode: String, Codable, CaseIterable {
    case discuss
    case quizMe
}

/// A conversational miss surfaces this from the server so the client can
/// show what specifically got flagged — the actual review-queue update
/// (SM-2) already happened server-side by the time this arrives.
struct AIRetentionAssessment: Codable, Hashable {
    enum Verdict: String, Codable {
        case solid, shaky, missed
    }
    var questionIds: [String]
    var verdict: Verdict
}

/// Mirrors `videos/{videoId}/aiThreads/{uid}/messages/{messageId}` — see
/// `aiTutorMessage`'s Firestore writes for the authoritative shape.
/// `status`/`suggestedReplies`/`retentionAssessment`/`promptVersion` are
/// only ever set on assistant messages; a user message simply omits them,
/// which decodes to `nil` here rather than needing a second message type.
struct AIMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable {
        case user, assistant
    }
    enum Status: String, Codable {
        case streaming, complete
    }

    @DocumentID var id: String? = nil
    var role: Role
    var mode: AIThreadMode
    var text: String
    var status: Status? = nil
    var suggestedReplies: [String]? = nil
    var retentionAssessment: AIRetentionAssessment? = nil
    var promptVersion: String? = nil
    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    var isStreaming: Bool { role == .assistant && status == .streaming }
}
