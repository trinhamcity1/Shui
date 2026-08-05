import XCTest
@testable import Shui

final class SearchKeywordsTests: XCTestCase {
    func testIndexesTitleWordsIndividually() {
        let keywords = SearchKeywords.index(
            title: "How to life live to the fullest",
            subtitle: "",
            description: "",
            tags: []
        )
        XCTAssertTrue(keywords.contains("fullest"))
        XCTAssertTrue(keywords.contains("life"))
        XCTAssertTrue(keywords.contains("live"))
    }

    func testIndexesTags() {
        let keywords = SearchKeywords.index(
            title: "Title",
            subtitle: "",
            description: "",
            tags: ["healing", "life", "enjoy", "personal", "development"]
        )
        XCTAssertTrue(keywords.contains("healing"))
        XCTAssertTrue(keywords.contains("development"))
    }

    func testMultiWordTagIsSplitIntoIndividualKeywords() {
        let keywords = SearchKeywords.index(
            title: "Title", subtitle: "", description: "", tags: ["personal development"]
        )
        XCTAssertTrue(keywords.contains("personal"))
        XCTAssertTrue(keywords.contains("development"))
    }

    func testQueryAndIndexTokenizeIdentically() {
        // The whole scheme only works if both sides agree on what a "word"
        // is — this pins that down directly rather than trusting it by
        // inspection.
        let indexed = SearchKeywords.index(title: "Healing & Growth", subtitle: "", description: "", tags: [])
        let queried = SearchKeywords.query("healing")
        XCTAssertTrue(Set(queried).isSubset(of: Set(indexed)))
    }

    func testDropsPunctuationAndVeryShortNoiseTokens() {
        let keywords = SearchKeywords.index(title: "A B, C-D! E?", subtitle: "", description: "", tags: [])
        XCTAssertFalse(keywords.contains("a"))
        XCTAssertFalse(keywords.contains("b"))
    }

    func testDeduplicates() {
        let keywords = SearchKeywords.index(title: "life life life", subtitle: "", description: "", tags: [])
        XCTAssertEqual(keywords.filter { $0 == "life" }.count, 1)
    }

    func testEmptyQueryProducesNoTokens() {
        XCTAssertTrue(SearchKeywords.query("   ").isEmpty)
    }

    func testCapsAtMaximumKeywordCount() {
        let longDescription = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let keywords = SearchKeywords.index(title: "", subtitle: "", description: longDescription, tags: [])
        XCTAssertLessThanOrEqual(keywords.count, 60)
    }
}
