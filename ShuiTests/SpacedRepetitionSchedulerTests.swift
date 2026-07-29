import XCTest
@testable import Shui

final class SpacedRepetitionSchedulerTests: XCTestCase {
    func testFailingResetsIntervalAndRepetitions() {
        var state = ReviewState.new()
        state.repetitions = 3
        state.intervalDays = 10

        let next = SpacedRepetitionScheduler.schedule(state, grade: .again)

        XCTAssertEqual(next.repetitions, 0)
        XCTAssertEqual(next.intervalDays, 1)
    }

    func testPassingGrowsIntervalAcrossRepetitions() {
        let now = Date()
        var state = ReviewState.new(now: now)

        state = SpacedRepetitionScheduler.schedule(state, grade: .good, now: now)
        XCTAssertEqual(state.repetitions, 1)
        XCTAssertEqual(state.intervalDays, 1)

        state = SpacedRepetitionScheduler.schedule(state, grade: .good, now: now)
        XCTAssertEqual(state.repetitions, 2)
        XCTAssertEqual(state.intervalDays, 6)

        let intervalBefore = state.intervalDays
        state = SpacedRepetitionScheduler.schedule(state, grade: .good, now: now)
        XCTAssertEqual(state.repetitions, 3)
        XCTAssertGreaterThan(state.intervalDays, intervalBefore)
    }

    func testEaseFactorNeverDropsBelowMinimum() {
        var state = ReviewState.new()
        for _ in 0..<25 {
            state = SpacedRepetitionScheduler.schedule(state, grade: .again)
        }
        XCTAssertGreaterThanOrEqual(state.easeFactor, SpacedRepetitionScheduler.minimumEaseFactor)
    }

    func testIsDueRespectsDueDate() {
        let now = Date()
        var state = ReviewState.new(now: now)

        state.dueDate = now.addingTimeInterval(3600)
        XCTAssertFalse(SpacedRepetitionScheduler.isDue(state, now: now))

        state.dueDate = now.addingTimeInterval(-3600)
        XCTAssertTrue(SpacedRepetitionScheduler.isDue(state, now: now))
    }

    func testNewStateIsImmediatelyDue() {
        let now = Date()
        let state = ReviewState.new(now: now)
        XCTAssertTrue(state.isNew)
        XCTAssertTrue(SpacedRepetitionScheduler.isDue(state, now: now))
    }

    func testScheduleDoesNotMutateTheInputState() {
        let original = ReviewState.new()
        _ = SpacedRepetitionScheduler.schedule(original, grade: .good)
        XCTAssertEqual(original.repetitions, 0)
        XCTAssertEqual(original.intervalDays, 0)
        XCTAssertNil(original.lastReviewedAt)
    }
}
