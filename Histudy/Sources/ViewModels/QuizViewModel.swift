import Foundation

@MainActor
final class QuizViewModel: ObservableObject {
    let question: CivicsQuestion
    @Published private(set) var options: [QuizOption]
    @Published var selected: Set<QuizOption> = []
    @Published private(set) var isSubmitted = false
    @Published private(set) var isCorrect = false

    private let requiredCorrect: Int

    /// False for a dynamic/user-specific question the learner hasn't filled
    /// in yet (e.g. their own Senators) — the view shows an info card
    /// instead of a graded quiz in that case.
    var isAnswerable: Bool { !options.isEmpty }
    var requiredCorrectCount: Int { requiredCorrect }

    init(question: CivicsQuestion, allQuestions: [CivicsQuestion], localOfficials: LocalOfficialsProfile) {
        self.question = question
        let built = QuizOptionBuilder.build(for: question, allQuestions: allQuestions, localOfficials: localOfficials)
        options = built.options
        requiredCorrect = built.requiredCorrect
    }

    func toggle(_ option: QuizOption) {
        guard !isSubmitted else { return }
        if selected.contains(option) {
            selected.remove(option)
        } else if requiredCorrect == 1 {
            selected = [option]
        } else if selected.count < requiredCorrect {
            selected.insert(option)
        }
    }

    var canSubmit: Bool {
        !isSubmitted && selected.count == requiredCorrect && requiredCorrect > 0
    }

    func submit() {
        guard canSubmit else { return }
        isSubmitted = true
        isCorrect = QuizGrader.isCorrect(selected: selected, requiredCorrect: requiredCorrect)
    }

    var correctAnswerSummary: String {
        options.filter(\.isCorrect).map(\.text).joined(separator: ", ")
    }
}
