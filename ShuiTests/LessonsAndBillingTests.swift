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
