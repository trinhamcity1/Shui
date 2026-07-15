import Foundation
import SwiftData

/// Free vs. pro tier, per the freemium spec. Stored on `UserProfile`.
/// Pro unlocks the AI tutor chat and advanced analytics; free keeps
/// lessons, quizzes, and community comments.
enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case pro
}

/// Simulated sign-in provider choice. Real OAuth (Google/Facebook/Instagram)
/// requires provider app registrations plus Firebase Auth or Cognito — see
/// README's backend workstream. Until that exists, the chosen provider is
/// recorded locally so the full sign-in → tier-selection flow is testable.
enum AuthProvider: String, Codable, CaseIterable {
    case google
    case facebook
    case instagram
}

/// A community comment on a lesson, threaded one level via `parentID`.
/// Local-first mirror of the spec's Comments table (comment ID, lesson ID,
/// user, text, timestamp, reply-to) so a remote sync service can replace
/// the local store without changing the UI.
@Model
final class LessonComment {
    var id: UUID = UUID()
    var lessonID: String = ""
    var authorName: String = ""
    var text: String = ""
    var timestamp: Date = Date()
    var parentID: UUID?

    init(lessonID: String, authorName: String, text: String, parentID: UUID? = nil) {
        self.id = UUID()
        self.lessonID = lessonID
        self.authorName = authorName
        self.text = text
        self.timestamp = Date()
        self.parentID = parentID
    }
}

/// One message in the pro AI tutor chat, kept per lesson. Local-first
/// mirror of the spec's Pro User Questions table (question, AI response,
/// lesson link, timestamp) — this history is also what lets the tutor
/// build on earlier questions within a lesson.
@Model
final class TutorChatMessage {
    var id: UUID = UUID()
    var lessonID: String = ""
    var isUser: Bool = false
    var text: String = ""
    var timestamp: Date = Date()

    init(lessonID: String, isUser: Bool, text: String) {
        self.id = UUID()
        self.lessonID = lessonID
        self.isUser = isUser
        self.text = text
        self.timestamp = Date()
    }
}
