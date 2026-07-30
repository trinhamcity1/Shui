import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}/videoProgress/{videoId}` — the per-video review
/// record, including the SM-2 fields. `submitQuizAttempt` is the only writer;
/// the scheduling math it runs must agree with
/// `Sources/Learning/SpacedRepetitionScheduler.swift` and its server port in
/// `functions/src/lib/sm2.ts`.
struct VideoProgress: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var videoId: String
    var topicId: String
    var watchedSeconds: Double
    var completed: Bool
    var completedAt: Date?
    var quizAttempts: Int
    var quizBestScore: Double
    var quizPassed: Bool
    var lastAnsweredAt: Date?
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date
}
