import XCTest
@testable import Shui

final class SessionPlannerTests: XCTestCase {
    func testNewUserGetsANonEmptySessionWithinBudget() {
        let questions = ContentStore.shared.questions
        let items = SessionPlanner.buildSession(allQuestions: questions, allProgress: [], targetMinutes: 7)
        XCTAssertFalse(items.isEmpty)
    }

    func testDueQuestionComesBeforeUnstudiedQuestions() {
        let questions = ContentStore.shared.questions
        let dueQuestion = questions[5]
        let dueProgress = QuestionProgress(questionId: dueQuestion.id)
        dueProgress.repetitions = 1
        dueProgress.lastReviewedAt = Date().addingTimeInterval(-86_400)
        dueProgress.dueDate = Date().addingTimeInterval(-3600)

        let items = SessionPlanner.buildSession(allQuestions: questions, allProgress: [dueProgress], targetMinutes: 10)

        XCTAssertEqual(items.first?.question.id, dueQuestion.id)
    }

    func testNotYetDueQuestionIsNotForcedIntoTodaysSession() {
        let questions = ContentStore.shared.questions
        let notDueProgress = QuestionProgress(questionId: questions[0].id)
        notDueProgress.repetitions = 1
        notDueProgress.lastReviewedAt = Date()
        notDueProgress.dueDate = Date().addingTimeInterval(86_400 * 5)

        let items = SessionPlanner.buildSession(allQuestions: questions, allProgress: [notDueProgress], targetMinutes: 30)

        XCTAssertFalse(items.contains { $0.question.id == questions[0].id })
    }

    func testSessionRespectsTimeBudgetButAlwaysIncludesAtLeastOneItem() {
        let questions = ContentStore.shared.questions
        let items = SessionPlanner.buildSession(allQuestions: questions, allProgress: [], targetMinutes: 1)
        XCTAssertEqual(items.count, 1, "an unreasonably small budget should still yield exactly one item, not zero")
    }
}
