import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}/topicProgress/{topicId}`. `masteryPercent` is
/// computed server-side from the same formula documented in
/// `functions/src/lib/mastery.ts` — watching without answering can never
/// exceed 40%, which is why this struct never recomputes it locally.
struct TopicProgress: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var topicId: String
    var topicTitle: String
    var categoryId: String
    var videosCompleted: Int
    var videosTotal: Int
    var quizzesAttempted: Int
    var quizzesPassed: Int
    var correctAnswers: Int
    var totalAnswers: Int
    var masteryPercent: Int
    var startedAt: Date?
    var lastActivityAt: Date?
}
