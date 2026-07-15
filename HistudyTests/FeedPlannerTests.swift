import XCTest
@testable import Histudy

final class FeedPlannerTests: XCTestCase {
    func testDueLessonOrdersBeforeNewLessons() {
        let questions = ContentStore.shared.questions
        let dueQuestion = questions[10]

        let dueProgress = QuestionProgress(questionId: dueQuestion.id)
        dueProgress.repetitions = 1
        dueProgress.lastReviewedAt = Date().addingTimeInterval(-86_400)
        dueProgress.dueDate = Date().addingTimeInterval(-3600)

        let ordered = FeedPlanner.orderedLessons(
            questions: questions,
            progressByID: [dueQuestion.id: dueProgress],
            lessonFor: { ContentStore.shared.lesson(for: $0) }
        )

        let dueLesson = ContentStore.shared.lesson(for: dueQuestion)
        XCTAssertEqual(ordered.first?.id, dueLesson.id)
    }

    func testFeedDeduplicatesMultiQuestionLessons() {
        let questions = ContentStore.shared.questions
        let ordered = FeedPlanner.orderedLessons(
            questions: questions,
            progressByID: [:],
            lessonFor: { ContentStore.shared.lesson(for: $0) }
        )
        let ids = ordered.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "the same lesson must not appear twice in the initial feed")
        XCTAssertFalse(ordered.isEmpty)
    }

    func testResurfaceIndexIsFivePagesLaterClampedToEnd() {
        XCTAssertEqual(FeedPlanner.resurfaceIndex(afterCurrentIndex: 0, feedCount: 100), 5)
        XCTAssertEqual(FeedPlanner.resurfaceIndex(afterCurrentIndex: 98, feedCount: 100), 100)
        XCTAssertEqual(FeedPlanner.resurfaceIndex(afterCurrentIndex: 0, feedCount: 3), 3)
    }
}
