import Foundation
import SwiftData

/// A quiz attempt that couldn't reach `submitQuizAttempt` — network failure,
/// airplane mode mid-quiz — kept so it can be resubmitted instead of
/// silently dropped. `answers` round-trips through JSON since SwiftData
/// can't store `[QuizAttemptAnswer]` directly.
@Model
final class PendingQuizAttempt {
    var id: UUID = UUID()
    var videoID: String = ""
    var answersData: Data = Data()
    var createdAt: Date = Date()

    init(videoID: String, answers: [QuizAttemptAnswer]) {
        self.id = UUID()
        self.videoID = videoID
        self.answersData = (try? JSONEncoder().encode(answers)) ?? Data()
        self.createdAt = Date()
    }

    var answers: [QuizAttemptAnswer] {
        (try? JSONDecoder().decode([QuizAttemptAnswer].self, from: answersData)) ?? []
    }
}
