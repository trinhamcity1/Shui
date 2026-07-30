import Foundation

struct QuizOption: Codable, Identifiable, Hashable {
    var id: String
    var text: String
}

struct QuizQuestion: Codable, Identifiable, Hashable {
    var id: String
    var prompt: String
    var options: [QuizOption]
    var requiredCorrectCount: Int
    var orderIndex: Int
}

/// Mirrors `videos/{videoId}/quiz/current` — prompts and options only. The
/// correct answers live server-side in the sibling `quiz/answers` document,
/// which rules make unreadable to anyone but the video's owner or an admin.
/// Grading happens in `submitQuizAttempt`; this client never sees an answer
/// key ahead of time.
struct Quiz: Codable, Hashable {
    var version: Int
    var questions: [QuizQuestion]
    var passThreshold: Double
    var updatedBy: String
    var updatedAt: Date?
}

struct QuizAttemptAnswer: Codable {
    var questionId: String
    var selectedOptionIds: [String]
}

struct QuizQuestionResult: Codable, Identifiable {
    var questionId: String
    var wasCorrect: Bool
    var correctOptionIds: [String]
    var explanation: String

    var id: String { questionId }
}

/// Return value of the `submitQuizAttempt` callable.
struct QuizResult: Codable {
    var score: Double
    var passed: Bool
    var results: [QuizQuestionResult]
}
