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

    func testZeroRequiredCorrectIsNeverCorrect() {
        let a = QuizOption(text: "A", isCorrect: true)
        XCTAssertFalse(QuizGrader.isCorrect(selected: [a], requiredCorrect: 0))
        XCTAssertFalse(QuizGrader.isCorrect(selected: [], requiredCorrect: 0))
    }
}
