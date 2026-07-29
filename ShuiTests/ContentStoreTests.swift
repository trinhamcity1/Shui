import XCTest
@testable import Shui

final class ContentStoreTests: XCTestCase {
    func testLoadsAllHundredQuestions() {
        let store = ContentStore.shared
        XCTAssertEqual(store.questions.count, 100)
        XCTAssertEqual(Set(store.questions.map(\.id)), Set(1...100))
    }

    func testLoadsAllCategories() {
        XCTAssertEqual(ContentStore.shared.categories.count, QuestionCategory.allCases.count)
    }

    func testEveryQuestionResolvesToALesson() {
        let store = ContentStore.shared
        for question in store.questions {
            let lesson = store.lesson(for: question)
            XCTAssertFalse(lesson.narration.isEmpty, "Question \(question.id) resolved to a lesson with no narration")
            XCTAssertFalse(lesson.actions.isEmpty, "Question \(question.id) resolved to a lesson with no scene actions")
        }
    }

    func testDynamicQuestionsHaveNoStaticAnswerBakedIn() {
        // Time-sensitive questions (current President, VP, etc.) must not
        // ship a hard-coded name — see CurrentOfficialsConfig doc comment.
        let store = ContentStore.shared
        let dynamicQuestions = store.questions.filter { $0.isDynamic }
        XCTAssertFalse(dynamicQuestions.isEmpty)
        for question in dynamicQuestions {
            XCTAssertTrue(question.answersEN.isEmpty, "Question \(question.id) is dynamic but ships a static answer")
        }
    }

    func testStateCapitalLookupCoversAllFiftyStates() {
        XCTAssertEqual(StateCapitalLookup.shared.allStateNames.count, 50)
        XCTAssertEqual(StateCapitalLookup.shared.capital(forState: "California"), "Sacramento")
    }

    func testResolvedAnswersFillsInUserStateCapital() {
        let store = ContentStore.shared
        guard let question = store.question(id: 44) else { return XCTFail("missing question 44") }
        var officials = LocalOfficialsProfile()
        officials.stateName = "Texas"
        let answers = store.resolvedAnswers(for: question, localOfficials: officials)
        XCTAssertEqual(answers, ["Austin"])
    }
}
