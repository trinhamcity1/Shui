import XCTest
@testable import Shui

final class QuizGradingTests: XCTestCase {
    func testGradesExactMatchAsCorrect() {
        let correct = QuizOption(text: "Correct", isCorrect: true)
        let wrong = QuizOption(text: "Wrong", isCorrect: false)
        XCTAssertTrue(QuizGrader.isCorrect(selected: [correct], requiredCorrect: 1))
        XCTAssertFalse(QuizGrader.isCorrect(selected: [wrong], requiredCorrect: 1))
    }

    func testMixingInAWrongOptionFailsTheAnswer() {
        let correct = QuizOption(text: "Correct", isCorrect: true)
        let wrong = QuizOption(text: "Wrong", isCorrect: false)
        XCTAssertFalse(QuizGrader.isCorrect(selected: [correct, wrong], requiredCorrect: 1))
    }

    func testMultiAnswerRequiresExactCount() {
        let a = QuizOption(text: "A", isCorrect: true)
        let b = QuizOption(text: "B", isCorrect: true)
        let c = QuizOption(text: "C", isCorrect: false)
        XCTAssertFalse(QuizGrader.isCorrect(selected: [a], requiredCorrect: 2))
        XCTAssertTrue(QuizGrader.isCorrect(selected: [a, b], requiredCorrect: 2))
        XCTAssertFalse(QuizGrader.isCorrect(selected: [a, c], requiredCorrect: 2))
    }

    func testOptionBuilderAlwaysIncludesACorrectOption() {
        let store = ContentStore.shared
        guard let question = store.question(id: 97) else { return XCTFail("missing question 97") }
        let (options, requiredCorrect) = QuizOptionBuilder.build(
            for: question, allQuestions: store.questions, localOfficials: LocalOfficialsProfile()
        )
        XCTAssertGreaterThan(requiredCorrect, 0)
        XCTAssertTrue(options.contains { $0.isCorrect })
        XCTAssertEqual(Set(options.map(\.text)).count, options.count, "options should not contain duplicate text")
    }

    func testOptionBuilderReturnsEmptyForUnresolvedDynamicQuestion() {
        let store = ContentStore.shared
        guard let question = store.question(id: 20) else { return XCTFail("missing question 20") }
        let (options, requiredCorrect) = QuizOptionBuilder.build(
            for: question, allQuestions: store.questions, localOfficials: LocalOfficialsProfile()
        )
        XCTAssertTrue(options.isEmpty)
        XCTAssertEqual(requiredCorrect, 0)
    }
}
