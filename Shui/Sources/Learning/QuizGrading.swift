import Foundation

/// A single selectable answer shown in the quiz UI.
struct QuizOption: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let isCorrect: Bool
}

/// Local grading, used for immediate UI feedback only.
///
/// Authoritative grading happens server-side in the `submitQuizAttempt`
/// callable: the client is never trusted with correctness, and the correct
/// answers are not readable ahead of time. This stays because the feed still
/// needs to render "you picked the right one" the instant the server responds,
/// without re-deriving the rule in the view layer.
enum QuizGrader {
    static func isCorrect(selected: Set<QuizOption>, requiredCorrect: Int) -> Bool {
        guard requiredCorrect > 0 else { return false }
        let correctSelected = selected.filter(\.isCorrect).count
        let incorrectSelected = selected.filter { !$0.isCorrect }.count
        return incorrectSelected == 0 && correctSelected == requiredCorrect
    }
}
