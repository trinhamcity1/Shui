import Foundation

/// A single selectable answer shown in the quiz UI. Multiple choice (rather
/// than free-text) is used deliberately: it grades unambiguously, keeps the
/// daily session fast, and avoids penalizing a language learner for a typo
/// in their second language.
struct QuizOption: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let isCorrect: Bool
}

/// Builds a multiple-choice question from a `CivicsQuestion`, resolving
/// dynamic/user-specific answers first and drawing distractors from other
/// questions in the same category (falling back to the whole bank if a
/// category is too small to supply enough wrong answers).
enum QuizOptionBuilder {
    static func build(
        for question: CivicsQuestion,
        allQuestions: [CivicsQuestion],
        localOfficials: LocalOfficialsProfile,
        optionCount: Int = 4
    ) -> (options: [QuizOption], requiredCorrect: Int) {
        let correctAnswers = ContentStore.shared.resolvedAnswers(for: question, localOfficials: localOfficials)
        guard !correctAnswers.isEmpty else { return ([], 0) }

        let maxCorrectShown = max(1, optionCount - 1)
        let shownCorrect = Array(correctAnswers.shuffled().prefix(maxCorrectShown))
        let correctOptions = shownCorrect.map { QuizOption(text: $0, isCorrect: true) }
        let correctLower = Set(correctAnswers.map { $0.lowercased() })

        var distractorPool = Array(Set(
            allQuestions
                .filter { $0.id != question.id && $0.category == question.category }
                .flatMap(\.answersEN)
        ))
        if distractorPool.count < optionCount {
            distractorPool = Array(Set(distractorPool + allQuestions
                .filter { $0.id != question.id }
                .flatMap(\.answersEN)))
        }
        distractorPool.removeAll { correctLower.contains($0.lowercased()) }

        let neededDistractors = max(1, optionCount - correctOptions.count)
        let distractors = distractorPool.shuffled().prefix(neededDistractors).map { QuizOption(text: $0, isCorrect: false) }

        let requiredCorrect = min(question.requiredAnswerCount, correctOptions.count)
        return ((correctOptions + distractors).shuffled(), requiredCorrect)
    }
}

enum QuizGrader {
    static func isCorrect(selected: Set<QuizOption>, requiredCorrect: Int) -> Bool {
        guard requiredCorrect > 0 else { return false }
        let correctSelected = selected.filter(\.isCorrect).count
        let incorrectSelected = selected.filter { !$0.isCorrect }.count
        return incorrectSelected == 0 && correctSelected == requiredCorrect
    }
}
