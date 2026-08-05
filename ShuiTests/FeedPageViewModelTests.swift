import XCTest
@testable import Shui

@MainActor
final class FeedPageViewModelTests: XCTestCase {
    private func makeVideo(hasQuiz: Bool = true) -> Video {
        Video(
            id: "v1",
            topicId: "topic-1",
            topicTitle: "Topic",
            categoryId: "exam-prep",
            topicVisibility: .public,
            title: "Video",
            description: "",
            order: 0,
            playbackURL: "https://example.com/v1.mp4",
            thumbnailURL: nil,
            durationSeconds: 30,
            aspectRatio: 0.5625,
            sizeBytes: 1000,
            transcript: nil,
            visibility: .public,
            status: .ready,
            statusMessage: nil,
            createdBy: "creator-1",
            createdAt: nil,
            updatedAt: nil,
            publishedAt: nil,
            hasQuiz: hasQuiz,
            likeCount: 0,
            commentCount: 0,
            viewCount: 0,
            completionCount: 0,
            isDeleted: false
        )
    }

    private func makeQuiz(questionCount: Int = 2, requiredCorrectCount: Int = 1) -> Quiz {
        let questions = (0..<questionCount).map { i in
            QuizQuestion(
                id: "q\(i)",
                prompt: "Prompt \(i)",
                options: [
                    QuizOption(id: "a", text: "A"),
                    QuizOption(id: "b", text: "B"),
                    QuizOption(id: "c", text: "C"),
                ],
                requiredCorrectCount: requiredCorrectCount,
                orderIndex: i
            )
        }
        return Quiz(version: 1, questions: questions, passThreshold: 0.6, updatedBy: "creator-1", updatedAt: nil)
    }

    func testVideoWithNoQuizGoesStraightToNoQuizState() {
        let page = FeedPageViewModel(video: makeVideo(hasQuiz: false), source: .everythingElse)
        page.videoDidEnd()
        XCTAssertEqual(page.endState, .noQuiz)
    }

    func testVideoEndingBeforeQuizPrefetchWaitsThenAnswers() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        page.videoDidEnd()
        XCTAssertEqual(page.endState, .loadingQuiz)

        page.quizDidLoad(makeQuiz())
        XCTAssertEqual(page.endState, .answering(questionIndex: 0))
    }

    func testVideoEndingAfterQuizAlreadyLoadedGoesStraightToAnswering() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        page.quizDidLoad(makeQuiz())
        XCTAssertEqual(page.endState, .loadingQuiz, "quizDidLoad only transitions out of .loadingQuiz, not .notEnded")

        page.videoDidEnd()
        XCTAssertEqual(page.endState, .answering(questionIndex: 0))
    }

    func testSingleSelectReplacesPriorChoiceInsteadOfAccumulating() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 1, requiredCorrectCount: 1)
        page.quizDidLoad(quiz)
        page.videoDidEnd()

        let question = quiz.questions[0]
        page.toggleOption("a", for: question)
        XCTAssertTrue(page.isOptionSelected("a", for: question))

        page.toggleOption("b", for: question)
        XCTAssertFalse(page.isOptionSelected("a", for: question), "picking b should replace a, not add to it")
        XCTAssertTrue(page.isOptionSelected("b", for: question))
    }

    func testMultiSelectStopsAcceptingNewSelectionsOnceAtTheRequiredCount() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 1, requiredCorrectCount: 2)
        page.quizDidLoad(quiz)
        page.videoDidEnd()

        let question = quiz.questions[0]
        page.toggleOption("a", for: question)
        page.toggleOption("b", for: question)
        XCTAssertTrue(page.canAdvance(question: question))

        page.toggleOption("c", for: question)
        XCTAssertFalse(page.isOptionSelected("c", for: question), "a third selection should be ignored once 2 of 2 are chosen")
        XCTAssertTrue(page.canAdvance(question: question))
    }

    func testCanAdvanceOnlyOnceExactlyTheRequiredCountIsSelected() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 1, requiredCorrectCount: 1)
        page.quizDidLoad(quiz)
        page.videoDidEnd()

        let question = quiz.questions[0]
        XCTAssertFalse(page.canAdvance(question: question))
        page.toggleOption("a", for: question)
        XCTAssertTrue(page.canAdvance(question: question))
    }

    func testAdvancingThroughAllButTheLastQuestionReturnsNilAndMovesForward() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 3)
        page.quizDidLoad(quiz)
        page.videoDidEnd()

        page.toggleOption("a", for: quiz.questions[0])
        XCTAssertNil(page.advanceAnswering())
        XCTAssertEqual(page.endState, .answering(questionIndex: 1))
    }

    func testAdvancingPastTheLastQuestionCollectsAllAnswersAndBeginsSubmitting() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 2)
        page.quizDidLoad(quiz)
        page.videoDidEnd()

        page.toggleOption("a", for: quiz.questions[0])
        _ = page.advanceAnswering()
        page.toggleOption("b", for: quiz.questions[1])
        let answers = page.advanceAnswering()

        XCTAssertEqual(page.endState, .submitting)
        XCTAssertEqual(answers?.count, 2)
        XCTAssertEqual(answers?.first(where: { $0.questionId == "q0" })?.selectedOptionIds, ["a"])
        XCTAssertEqual(answers?.first(where: { $0.questionId == "q1" })?.selectedOptionIds, ["b"])
    }

    func testReceivingAResultMovesToRevealingAllQuestionsAtOnce() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 2)
        page.quizDidLoad(quiz)
        page.videoDidEnd()
        page.toggleOption("a", for: quiz.questions[0])
        _ = page.advanceAnswering()
        page.toggleOption("a", for: quiz.questions[1])
        _ = page.advanceAnswering()

        let result = QuizResult(
            score: 1,
            passed: true,
            results: [
                QuizQuestionResult(questionId: "q0", wasCorrect: true, correctOptionIds: ["a"], explanation: "because"),
                QuizQuestionResult(questionId: "q1", wasCorrect: true, correctOptionIds: ["a"], explanation: "because"),
            ]
        )
        page.receiveResult(result, masteryDelta: 5)

        XCTAssertEqual(page.endState, .revealingAll)
        XCTAssertEqual(page.masteryDelta, 5)
        let items = page.allRevealItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.question.id, "q0")
        XCTAssertEqual(items.last?.question.id, "q1")
    }

    func testFinishingRevealReachesResult() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 2)
        page.quizDidLoad(quiz)
        page.videoDidEnd()
        page.toggleOption("a", for: quiz.questions[0])
        _ = page.advanceAnswering()
        page.toggleOption("a", for: quiz.questions[1])
        _ = page.advanceAnswering()

        let result = QuizResult(
            score: 1,
            passed: true,
            results: [
                QuizQuestionResult(questionId: "q0", wasCorrect: true, correctOptionIds: ["a"], explanation: ""),
                QuizQuestionResult(questionId: "q1", wasCorrect: true, correctOptionIds: ["a"], explanation: ""),
            ]
        )
        page.receiveResult(result, masteryDelta: nil)

        page.finishReveal()
        XCTAssertEqual(page.endState, .result)
    }

    func testFailedSubmissionCanBeRetriedWithTheSameAnswers() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 1)
        page.quizDidLoad(quiz)
        page.videoDidEnd()
        page.toggleOption("a", for: quiz.questions[0])
        _ = page.advanceAnswering()

        page.failSubmission()
        XCTAssertEqual(page.endState, .submissionFailed)

        let retryAnswers = page.collectAnswersForRetry()
        XCTAssertEqual(retryAnswers.first?.selectedOptionIds, ["a"])
    }

    func testReplayResetsAnsweringAndTrackingState() {
        let page = FeedPageViewModel(video: makeVideo(), source: .everythingElse)
        let quiz = makeQuiz(questionCount: 1)
        page.quizDidLoad(quiz)
        page.videoDidEnd()
        page.toggleOption("a", for: quiz.questions[0])
        page.hasRecordedView = true
        page.hasMarkedCompleted = true

        page.replay()

        XCTAssertEqual(page.endState, .notEnded)
        XCTAssertFalse(page.isOptionSelected("a", for: quiz.questions[0]))
        XCTAssertFalse(page.hasRecordedView)
        XCTAssertFalse(page.hasMarkedCompleted)
    }
}
