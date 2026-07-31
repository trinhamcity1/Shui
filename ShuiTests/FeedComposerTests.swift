import XCTest
@testable import Shui

final class FeedComposerTests: XCTestCase {
    private func makeVideo(_ id: String) -> Video {
        Video(
            id: id,
            topicId: "topic-1",
            topicTitle: "Topic",
            categoryId: "exam-prep",
            topicVisibility: .public,
            title: "Video \(id)",
            description: "",
            order: 0,
            playbackURL: "https://example.com/\(id).mp4",
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
            hasQuiz: true,
            likeCount: 0,
            commentCount: 0,
            viewCount: 0,
            completionCount: 0,
            isDeleted: false
        )
    }

    private func makeVideos(_ prefix: String, _ count: Int) -> [Video] {
        (0..<count).map { makeVideo("\(prefix)-\($0)") }
    }

    func testReviewItemsComeFirstWhenBudgetAllows() {
        let review = makeVideos("review", 2)
        let items = FeedComposer.compose(
            dueForReview: review,
            continueTopic: makeVideos("continue", 5),
            newInInterests: [],
            everythingElse: []
        )
        XCTAssertEqual(items[0].source, .dueForReview)
        XCTAssertEqual(items[1].source, .dueForReview)
        XCTAssertEqual(items[0].video.id, "review-0")
        XCTAssertEqual(items[1].video.id, "review-1")
    }

    func testNeverMoreThanThreeReviewItemsInARow() {
        let review = makeVideos("review", 20)
        let filler = makeVideos("filler", 20)
        let items = FeedComposer.compose(
            dueForReview: review,
            continueTopic: filler,
            newInInterests: [],
            everythingElse: []
        )

        var consecutiveReview = 0
        for item in items {
            if item.source == .dueForReview {
                consecutiveReview += 1
                XCTAssertLessThanOrEqual(consecutiveReview, FeedComposer.maxConsecutiveReview)
            } else {
                consecutiveReview = 0
            }
        }
    }

    func testReviewItemsCappedAtFortyPercentOfAnyTenItemWindow() {
        let review = makeVideos("review", 30)
        let filler = makeVideos("filler", 30)
        let items = FeedComposer.compose(
            dueForReview: review,
            continueTopic: filler,
            newInInterests: [],
            everythingElse: []
        )

        guard items.count >= FeedComposer.reviewWindowSize else {
            return XCTFail("test needs at least a full window of items")
        }
        for start in 0...(items.count - FeedComposer.reviewWindowSize) {
            let window = items[start..<(start + FeedComposer.reviewWindowSize)]
            let reviewCount = window.filter { $0.source == .dueForReview }.count
            XCTAssertLessThanOrEqual(reviewCount, FeedComposer.maxReviewPerWindow)
        }
    }

    func testFallsBackToPlainReviewRunWhenNothingElseIsLeft() {
        // Only review items available at all — the spacing constraint can't
        // be honored without producing an empty feed, so review items still
        // get placed back to back rather than the feed coming up short.
        let review = makeVideos("review", 5)
        let items = FeedComposer.compose(
            dueForReview: review,
            continueTopic: [],
            newInInterests: [],
            everythingElse: []
        )
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.allSatisfy { $0.source == .dueForReview })
    }

    func testDeduplicatesByVideoIdAcrossBuckets() {
        let shared = makeVideo("shared-1")
        let items = FeedComposer.compose(
            dueForReview: [shared],
            continueTopic: [shared],
            newInInterests: [shared],
            everythingElse: [shared]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].source, .dueForReview)
    }

    func testDedupAccountsForItemsAlreadyPlacedInEarlierBatches() {
        let alreadyPlaced = [FeedItem(video: makeVideo("v-0"), source: .newInInterests)]
        let items = FeedComposer.compose(
            dueForReview: [],
            continueTopic: [],
            newInInterests: [makeVideo("v-0"), makeVideo("v-1")],
            everythingElse: [],
            alreadyPlaced: alreadyPlaced
        )
        XCTAssertEqual(items.map(\.video.id), ["v-1"])
    }

    func testOrderingIsStableAcrossRepeatedCalls() {
        let review = makeVideos("review", 12)
        let continueTopic = makeVideos("continue", 12)
        let newInInterests = makeVideos("new", 12)
        let everythingElse = makeVideos("rest", 12)

        let first = FeedComposer.compose(
            dueForReview: review, continueTopic: continueTopic,
            newInInterests: newInInterests, everythingElse: everythingElse
        )
        let second = FeedComposer.compose(
            dueForReview: review, continueTopic: continueTopic,
            newInInterests: newInInterests, everythingElse: everythingElse
        )
        XCTAssertEqual(first, second)
    }

    func testFallsThroughSourcesInPriorityOrder() {
        let items = FeedComposer.compose(
            dueForReview: [],
            continueTopic: makeVideos("continue", 2),
            newInInterests: makeVideos("new", 2),
            everythingElse: makeVideos("rest", 2)
        )
        XCTAssertEqual(items.map(\.source), [.continueTopic, .continueTopic, .newInInterests, .newInInterests, .everythingElse, .everythingElse])
    }
}
