import Foundation
import SwiftData

/// Per-question mastery state, driving the spaced-repetition scheduler.
/// This is the concrete "AI personalization" mechanism in the MVP: each
/// answer adjusts when and how often a question resurfaces, and the
/// `SessionPlanner` uses it to build a different session for every user
/// based on their actual performance instead of a fixed curriculum order.
@Model
final class QuestionProgress {
    @Attribute(.unique) var questionId: Int
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date
    var timesCorrect: Int
    var timesIncorrect: Int
    var lessonWatched: Bool
    var lastReviewedAt: Date?

    init(questionId: Int) {
        self.questionId = questionId
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = .distantPast // new cards are immediately due
        self.timesCorrect = 0
        self.timesIncorrect = 0
        self.lessonWatched = false
        self.lastReviewedAt = nil
    }

    var isNew: Bool { repetitions == 0 && lastReviewedAt == nil }

    /// 0 = new, 1 = learning, 2 = review, 3 = mastered. Drives progress UI
    /// (e.g. category mastery rings) without exposing the raw SM-2 fields.
    var masteryLevel: Int { min(3, repetitions) }

    var accuracy: Double {
        let total = timesCorrect + timesIncorrect
        guard total > 0 else { return 0 }
        return Double(timesCorrect) / Double(total)
    }
}
