import XCTest
@testable import Shui

final class SpacedRepetitionSchedulerTests: XCTestCase {
    func testFailingResetsIntervalAndRepetitions() {
        let progress = QuestionProgress(questionId: 1)
        progress.repetitions = 3
        progress.intervalDays = 10

        SpacedRepetitionScheduler.schedule(progress, grade: .again)

        XCTAssertEqual(progress.repetitions, 0)
        XCTAssertEqual(progress.intervalDays, 1)
        XCTAssertEqual(progress.timesIncorrect, 1)
    }

    func testPassingGrowsIntervalAcrossRepetitions() {
        let progress = QuestionProgress(questionId: 1)
        let now = Date()

        SpacedRepetitionScheduler.schedule(progress, grade: .good, now: now)
        XCTAssertEqual(progress.repetitions, 1)
        XCTAssertEqual(progress.intervalDays, 1)

        SpacedRepetitionScheduler.schedule(progress, grade: .good, now: now)
        XCTAssertEqual(progress.repetitions, 2)
        XCTAssertEqual(progress.intervalDays, 6)

        let intervalBefore = progress.intervalDays
        SpacedRepetitionScheduler.schedule(progress, grade: .good, now: now)
        XCTAssertEqual(progress.repetitions, 3)
        XCTAssertGreaterThan(progress.intervalDays, intervalBefore)
    }

    func testEaseFactorNeverDropsBelowMinimum() {
        let progress = QuestionProgress(questionId: 1)
        for _ in 0..<25 {
            SpacedRepetitionScheduler.schedule(progress, grade: .again)
        }
        XCTAssertGreaterThanOrEqual(progress.easeFactor, SpacedRepetitionScheduler.minimumEaseFactor)
    }

    func testIsDueRespectsDueDate() {
        let progress = QuestionProgress(questionId: 1)
        let now = Date()
        progress.dueDate = now.addingTimeInterval(3600)
        XCTAssertFalse(SpacedRepetitionScheduler.isDue(progress, now: now))

        progress.dueDate = now.addingTimeInterval(-3600)
        XCTAssertTrue(SpacedRepetitionScheduler.isDue(progress, now: now))
    }

    func testNewProgressIsImmediatelyDue() {
        let progress = QuestionProgress(questionId: 1)
        XCTAssertTrue(progress.isNew)
    }
}
