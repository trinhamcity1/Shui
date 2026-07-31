import Foundation

/// Where a feed page sits in the video -> quiz -> result loop. `notEnded`
/// covers active playback; everything else is post-video. Deliberately
/// separate from `PlaybackState` (owned by `FeedPlayerPool`) — this is about
/// what's *layered on top* of the paused final frame, not the player itself.
enum LessonEndState: Equatable {
    case notEnded
    /// The video ended before its quiz finished prefetching — rare (quizzes
    /// are prefetched well ahead of playback reaching the end), but real.
    case loadingQuiz
    case noQuiz
    case answering(questionIndex: Int)
    case submitting
    case submissionFailed
    case revealing(questionIndex: Int)
    case result
}

/// One instance per video in the feed. Owns quiz UI state and its
/// transitions; owns *no* network access — `FeedViewModel` calls
/// `advanceAnswering()` to collect the final answer set, submits it, and
/// reports the outcome back via `receiveResult`/`failSubmission`.
@MainActor
final class FeedPageViewModel: ObservableObject, Identifiable {
    let video: Video
    let source: FeedSource

    @Published private(set) var endState: LessonEndState = .notEnded
    @Published private(set) var quiz: Quiz?
    @Published private(set) var selectedOptionsByQuestion: [String: Set<String>] = [:]
    @Published private(set) var quizResult: QuizResult?
    @Published private(set) var masteryDelta: Int?
    @Published var isLiked = false
    @Published var likeCount: Int
    @Published var commentCount: Int
    var hasRecordedView = false
    var hasMarkedCompleted = false

    var id: String { video.id ?? video.playbackURL }

    init(video: Video, source: FeedSource) {
        self.video = video
        self.source = source
        self.likeCount = video.likeCount
        self.commentCount = video.commentCount
    }

    private var sortedQuestions: [QuizQuestion] {
        (quiz?.questions ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Quiz prefetch

    /// Called by `FeedViewModel` once the quiz for this video has loaded,
    /// which normally happens well before the video ever reaches its end.
    func quizDidLoad(_ quiz: Quiz?) {
        self.quiz = quiz
        guard endState == .loadingQuiz else { return }
        endState = (quiz?.questions.isEmpty ?? true) ? .noQuiz : .answering(questionIndex: 0)
    }

    // MARK: - Ending the video

    func videoDidEnd() {
        guard endState == .notEnded else { return }
        guard video.hasQuiz else {
            endState = .noQuiz
            return
        }
        if let quiz, !quiz.questions.isEmpty {
            endState = .answering(questionIndex: 0)
        } else if quiz != nil {
            // Loaded, but genuinely empty — treat like no quiz rather than
            // getting stuck waiting for questions that will never arrive.
            endState = .noQuiz
        } else {
            endState = .loadingQuiz
        }
    }

    func replay() {
        endState = .notEnded
        selectedOptionsByQuestion = [:]
        quizResult = nil
        masteryDelta = nil
        // A replay is a fresh watch-through for tracking purposes.
        hasRecordedView = false
        hasMarkedCompleted = false
    }

    // MARK: - Answering

    func currentQuestion() -> QuizQuestion? {
        guard case .answering(let index) = endState, sortedQuestions.indices.contains(index) else { return nil }
        return sortedQuestions[index]
    }

    func questionNumber() -> (current: Int, total: Int)? {
        guard case .answering(let index) = endState else { return nil }
        return (index + 1, sortedQuestions.count)
    }

    func isOptionSelected(_ optionId: String, for question: QuizQuestion) -> Bool {
        selectedOptionsByQuestion[question.id]?.contains(optionId) ?? false
    }

    func toggleOption(_ optionId: String, for question: QuizQuestion) {
        var selected = selectedOptionsByQuestion[question.id] ?? []
        if question.requiredCorrectCount <= 1 {
            selected = selected.contains(optionId) ? [] : [optionId]
        } else if selected.contains(optionId) {
            selected.remove(optionId)
        } else if selected.count < question.requiredCorrectCount {
            selected.insert(optionId)
        }
        selectedOptionsByQuestion[question.id] = selected
    }

    func canAdvance(question: QuizQuestion) -> Bool {
        (selectedOptionsByQuestion[question.id]?.count ?? 0) == question.requiredCorrectCount
    }

    func isLastQuestion() -> Bool {
        guard case .answering(let index) = endState else { return false }
        return index == sortedQuestions.count - 1
    }

    /// Moves to the next question, or — from the last question — transitions
    /// to `.submitting` and returns the full collected answer set for
    /// `FeedViewModel` to actually submit. Returns `nil` when there's
    /// another question still to answer.
    func advanceAnswering() -> [QuizAttemptAnswer]? {
        guard case .answering(let index) = endState else { return nil }
        if index < sortedQuestions.count - 1 {
            endState = .answering(questionIndex: index + 1)
            return nil
        }
        endState = .submitting
        return sortedQuestions.map { question in
            QuizAttemptAnswer(
                questionId: question.id,
                selectedOptionIds: Array(selectedOptionsByQuestion[question.id] ?? [])
            )
        }
    }

    func collectAnswersForRetry() -> [QuizAttemptAnswer] {
        sortedQuestions.map { question in
            QuizAttemptAnswer(
                questionId: question.id,
                selectedOptionIds: Array(selectedOptionsByQuestion[question.id] ?? [])
            )
        }
    }

    // MARK: - Submission outcome

    func beginSubmitting() {
        endState = .submitting
    }

    func receiveResult(_ result: QuizResult, masteryDelta: Int?) {
        quizResult = result
        self.masteryDelta = masteryDelta
        endState = sortedQuestions.isEmpty ? .result : .revealing(questionIndex: 0)
    }

    func failSubmission() {
        endState = .submissionFailed
    }

    // MARK: - Revealing

    func revealForCurrentQuestion() -> (question: QuizQuestion, result: QuizQuestionResult)? {
        guard case .revealing(let index) = endState,
              sortedQuestions.indices.contains(index),
              let quizResult
        else { return nil }
        let question = sortedQuestions[index]
        guard let result = quizResult.results.first(where: { $0.questionId == question.id }) else { return nil }
        return (question, result)
    }

    func advanceReveal() {
        guard case .revealing(let index) = endState else { return }
        endState = index < sortedQuestions.count - 1 ? .revealing(questionIndex: index + 1) : .result
    }
}
