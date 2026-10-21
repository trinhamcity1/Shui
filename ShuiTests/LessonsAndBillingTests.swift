import XCTest
@testable import Shui

/// Pure-logic coverage for phase-07's iOS layer — the state machine and
/// display formatting only; the repositories themselves are thin Firebase
/// wrappers with nothing pure to unit test without a live/emulated backend,
/// same convention every other repository in this codebase follows.
final class LessonsAndBillingTests: XCTestCase {
    // MARK: - LessonCreationStage

    func testIdleIsNotBusy() {
        XCTAssertFalse(LessonCreationStage.idle.isBusy)
    }

    func testGeneratingIsBusy() {
        XCTAssertTrue(LessonCreationStage.generating.isBusy)
    }

    func testReadyIsNotBusy() {
        XCTAssertFalse(LessonCreationStage.ready(videoId: "v1").isBusy)
    }

    func testFailedIsNotBusy() {
        XCTAssertFalse(LessonCreationStage.failed(message: "oops", canRetry: true).isBusy)
    }

    // MARK: - Topic.personalTopicId

    func testPersonalTopicIdMirrorsServerFormat() {
        // Must match `personalTopicId(uid)` in
        // functions/src/lib/onDemandVideo.ts exactly — both sides compute
        // this independently, so a drift here is silent until a query
        // simply returns nothing.
        XCTAssertEqual(Topic.personalTopicId(uid: "abc123"), "personal-abc123")
    }

    // MARK: - TierInfo

    func testTierInfoLookupMatchesRequestedTier() {
        for tier in Wallet.Tier.allCases {
            XCTAssertEqual(TierInfo.info(for: tier).tier, tier)
        }
    }

    func testOnlyPaidTiersHaveAStoreKitProductId() {
        XCTAssertNil(TierInfo.info(for: .free).productId)
        XCTAssertNil(TierInfo.info(for: .siltstone).productId)
        XCTAssertEqual(TierInfo.info(for: .obsidian).productId, "com.shui.app.tier.obsidian.monthly")
        XCTAssertEqual(TierInfo.info(for: .alabaster).productId, "com.shui.app.tier.alabaster.monthly")
        XCTAssertEqual(TierInfo.info(for: .pyramidion).productId, "com.shui.app.tier.pyramidion.monthly")
    }

    // MARK: - Lesson lengths and prices

    // Every expectation below mirrors functions/src/lib/tiers.test.ts — the
    // app only displays these, the server charges, so a drift here is a
    // price shown that isn't the price paid.

    func testEachTierAllowsLengthsUpToItsCap() {
        func allowed(_ tier: Wallet.Tier) -> [LessonDuration] {
            LessonDuration.allCases.filter(TierInfo.info(for: tier).allows)
        }
        XCTAssertEqual(allowed(.free), [.thirtySeconds])
        XCTAssertEqual(allowed(.siltstone), [.thirtySeconds, .oneMinute])
        XCTAssertEqual(allowed(.obsidian), [.thirtySeconds, .oneMinute])
        XCTAssertEqual(allowed(.alabaster), LessonDuration.allCases)
        XCTAssertEqual(allowed(.pyramidion), LessonDuration.allCases)
    }

    func testLessonPriceIsProRatedFromTheTierRate() {
        let obsidian = TierInfo.info(for: .obsidian)
        XCTAssertEqual(obsidian.costCents(for: .thirtySeconds), 200)
        XCTAssertEqual(obsidian.costCents(for: .oneMinute), 400)
        let alabaster = TierInfo.info(for: .alabaster)
        XCTAssertEqual(alabaster.costCents(for: .ninetySeconds), 600)
        XCTAssertEqual(alabaster.costCents(for: .twoMinutes), 800)
    }

    func testLockedLengthNamesTheCheapestTierThatUnlocksIt() {
        XCTAssertEqual(TierInfo.minimumTier(for: .oneMinute)?.tier, .siltstone)
        XCTAssertEqual(TierInfo.minimumTier(for: .ninetySeconds)?.tier, .alabaster)
        XCTAssertEqual(TierInfo.minimumTier(for: .twoMinutes)?.tier, .alabaster)
    }

    func testDurationRawValuesMatchTheServerSpelling() {
        XCTAssertEqual(LessonDuration.allCases.map(\.rawValue), ["0.5", "1", "1.5", "2"])
    }

    func testPlatformFormatsMapToTheTwoRealSizes() {
        for format in [LessonFormat.vertical, .tiktok, .instagramReels, .facebookReels, .youtubeShorts] {
            XCTAssertEqual(format.orientation, .vertical, format.title)
        }
        for format in [LessonFormat.horizontal, .youtube] {
            XCTAssertEqual(format.orientation, .horizontal, format.title)
        }
    }

    // MARK: - Wallet / CreditTransaction display formatting

    func testCreditBalanceDisplayFormatsCentsAsDollars() {
        let wallet = Wallet(
            tier: .obsidian, creditBalanceCents: 2250, hasUsedFreeLesson: true, appAccountToken: "t",
            appleOriginalTransactionId: nil, appleSubscriptionProductId: nil, likeRefundCentsThisCycle: 0,
            aiCycleStart: nil, aiCycleEnd: nil, aiSpentNanodollarsThisCycle: 0,
            cumulativeLikesReceived: 0, cumulativeLikesAccountedFor: 0
        )
        XCTAssertEqual(wallet.creditBalanceDisplay, "$22.50")
    }

    func testTransactionAmountDisplaySignsDebitsAndCredits() {
        let debit = CreditTransaction(id: nil, type: .lessonDebit, amountCents: -400, relatedVideoId: nil, relatedAppleTransactionId: nil, note: nil, createdAt: nil)
        let credit = CreditTransaction(id: nil, type: .topup, amountCents: 550, relatedVideoId: nil, relatedAppleTransactionId: nil, note: nil, createdAt: nil)
        XCTAssertEqual(debit.amountDisplay, "-$4.00")
        XCTAssertEqual(credit.amountDisplay, "+$5.50")
    }
}
