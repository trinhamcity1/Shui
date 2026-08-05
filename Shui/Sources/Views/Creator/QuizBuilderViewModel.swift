import Foundation

/// Mirrors `functions/src/schemas/quiz.ts` exactly. The point of duplicating
/// the rules client-side isn't to replace the server check — `saveQuiz`
/// still rejects a bad quiz — it's so a save never fails for a reason the UI
/// could have shown inline first (prompts/phase-05-creator-mode.md §5).
///
/// Kept as a free function over a draft rather than a method so it can be
/// exercised against arbitrary drafts without standing up a view model.
enum QuizValidation {
    static func errors(for question: QuizQuestionDraft) -> [String] {
        var items: [String] = []
        if question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("Question text is required.")
        }
        if question.options.count < 2 {
            items.append("Needs at least 2 options.")
        }
        if question.options.count > 6 {
            items.append("Allows at most 6 options.")
        }
        if question.options.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            items.append("Every option needs text.")
        }
        if question.correctOptionIds.isEmpty {
            items.append("Mark at least one option correct.")
        }
        // The explanation is required in the UI even though the schema only
        // demands a non-empty string — it's where the learning actually
        // happens, and skipping it is the easiest way to make the app worse.
        if question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("An explanation is required — it's what a learner reads after answering.")
        }
        if question.requiredCorrectCount > question.correctOptionIds.count {
            items.append("Required correct count is higher than the number of correct options.")
        }
        if question.requiredCorrectCount < 1 {
            items.append("Required correct count must be at least 1.")
        }
        return items
    }

    static func quizLevelErrors(_ questions: [QuizQuestionDraft]) -> [String] {
        var items: [String] = []
        if questions.isEmpty { items.append("A quiz needs at least 1 question.") }
        if questions.count > 5 { items.append("A quiz allows at most 5 questions.") }
        return items
    }
}

@MainActor
final class QuizBuilderViewModel: ObservableObject {
    @Published var questions: [QuizQuestionDraft] = []
    @Published var passThreshold: Double = 0.6
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDrafting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let video: Video
    private let environment: AppEnvironment

    init(video: Video, environment: AppEnvironment) {
        self.video = video
        self.environment = environment
    }

    var quizErrors: [String] { QuizValidation.quizLevelErrors(questions) }

    var isValid: Bool {
        quizErrors.isEmpty && questions.allSatisfy { QuizValidation.errors(for: $0).isEmpty }
    }

    var canAddQuestion: Bool { questions.count < 5 }
    var hasTranscript: Bool { !(video.transcript ?? "").isEmpty }

    /// Set when a local draft is newer than what the server returned, so the
    /// view can offer it rather than silently clobbering either side.
    @Published private(set) var recoverableDraft: CreatorDraftStore.QuizDraft?

    func load() async {
        guard let videoId = video.id else { return }
        isLoading = true
        defer { isLoading = false }
        questions = (try? await environment.quizzes.editableQuiz(forVideo: videoId)) ?? []
        if let existing = try? await environment.quizzes.quiz(forVideo: videoId) {
            passThreshold = existing.passThreshold
        }
        // Offered, never auto-applied: the same quiz may have been edited on
        // another device, and silently preferring the local copy would be
        // its own kind of data loss.
        if let draft = CreatorDraftStore.quizDraft(videoId: videoId) {
            recoverableDraft = draft
        }
    }

    func restoreDraft() {
        guard let draft = recoverableDraft else { return }
        questions = draft.questions
        passThreshold = draft.passThreshold
        recoverableDraft = nil
    }

    func discardDraft() {
        guard let videoId = video.id else { return }
        CreatorDraftStore.clearQuizDraft(videoId: videoId)
        recoverableDraft = nil
    }

    /// Called on every edit. Cheap enough to run per keystroke — a handful
    /// of questions encodes to a few KB.
    func persistDraftLocally() {
        guard let videoId = video.id else { return }
        CreatorDraftStore.saveQuizDraft(
            CreatorDraftStore.QuizDraft(questions: questions, passThreshold: passThreshold, savedAt: Date()),
            videoId: videoId
        )
    }

    func addQuestion() {
        guard canAddQuestion else { return }
        let optionIds = [UUID().uuidString, UUID().uuidString]
        questions.append(
            QuizQuestionDraft(
                id: UUID().uuidString,
                prompt: "",
                options: [
                    QuizOption(id: optionIds[0], text: ""),
                    QuizOption(id: optionIds[1], text: ""),
                ],
                correctOptionIds: [],
                requiredCorrectCount: 1,
                explanation: "",
                orderIndex: questions.count
            )
        )
    }

    func removeQuestion(at index: Int) {
        guard questions.indices.contains(index) else { return }
        questions.remove(at: index)
        reindex()
    }

    func move(from source: IndexSet, to destination: Int) {
        questions.move(fromOffsets: source, toOffset: destination)
        reindex()
    }

    func addOption(toQuestionAt index: Int) {
        guard questions.indices.contains(index), questions[index].options.count < 6 else { return }
        questions[index].options.append(QuizOption(id: UUID().uuidString, text: ""))
    }

    func removeOption(_ optionId: String, fromQuestionAt index: Int) {
        guard questions.indices.contains(index), questions[index].options.count > 2 else { return }
        questions[index].options.removeAll { $0.id == optionId }
        questions[index].correctOptionIds.removeAll { $0 == optionId }
        syncRequiredCount(at: index)
    }

    func toggleCorrect(_ optionId: String, forQuestionAt index: Int) {
        guard questions.indices.contains(index) else { return }
        if questions[index].correctOptionIds.contains(optionId) {
            questions[index].correctOptionIds.removeAll { $0 == optionId }
        } else {
            questions[index].correctOptionIds.append(optionId)
        }
        syncRequiredCount(at: index)
    }

    /// Auto-set to the number marked correct, but still overridable — the
    /// spec asks for both, and the auto-set is what makes the common
    /// single-answer case need no thought at all.
    private func syncRequiredCount(at index: Int) {
        guard questions.indices.contains(index) else { return }
        questions[index].requiredCorrectCount = max(1, questions[index].correctOptionIds.count)
    }

    private func reindex() {
        for index in questions.indices {
            questions[index].orderIndex = index
        }
    }

    func draftWithAI() async {
        guard let videoId = video.id else { return }
        isDrafting = true
        errorMessage = nil
        defer { isDrafting = false }
        do {
            let remaining = max(0, 5 - questions.count)
            guard remaining > 0 else {
                errorMessage = "A quiz can hold at most 5 questions."
                return
            }
            let drafted = try await environment.quizzes.suggestQuestions(videoId: videoId, count: min(3, remaining))
            // Appended, never auto-saved — the creator reviews and edits
            // before anything is written (§5).
            questions.append(contentsOf: drafted)
            reindex()
            successMessage = "Drafted \(drafted.count) question(s). Review and edit before saving."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> Bool {
        guard let videoId = video.id, isValid else { return false }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            let trimmed = questions.map { question -> QuizQuestionDraft in
                var copy = question
                copy.prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.explanation = question.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.options = question.options.map {
                    QuizOption(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return copy
            }
            try await environment.quizzes.saveQuiz(videoId: videoId, questions: trimmed, passThreshold: passThreshold)
            // Only cleared once the server has actually accepted it — that's
            // the whole point of keeping the local copy.
            CreatorDraftStore.clearQuizDraft(videoId: videoId)
            recoverableDraft = nil
            successMessage = "Quiz saved."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The exact shape the learner-facing quiz card renders, so Preview shows
    /// the real thing rather than an approximation of it.
    var previewQuiz: Quiz {
        Quiz(
            version: 0,
            questions: questions.map {
                QuizQuestion(
                    id: $0.id,
                    prompt: $0.prompt.isEmpty ? "Untitled question" : $0.prompt,
                    options: $0.options,
                    requiredCorrectCount: $0.requiredCorrectCount,
                    orderIndex: $0.orderIndex
                )
            },
            passThreshold: passThreshold,
            updatedBy: "",
            updatedAt: nil
        )
    }
}
