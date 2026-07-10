import Foundation
import SwiftData

/// A record of one completed 5-10 minute study session, used to render the
/// progress dashboard and to feed session summaries to the AI tutor layer.
@Model
final class SessionLog {
    var id: UUID
    var date: Date
    var durationSeconds: Double
    var lessonIdsWatched: [Int]
    var questionIds: [Int]
    var questionsCorrect: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Double = 0,
        lessonIdsWatched: [Int] = [],
        questionIds: [Int] = [],
        questionsCorrect: Int = 0
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.lessonIdsWatched = lessonIdsWatched
        self.questionIds = questionIds
        self.questionsCorrect = questionsCorrect
    }

    var questionsAnswered: Int { questionIds.count }
}
