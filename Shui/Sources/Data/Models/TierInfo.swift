import Foundation

/// Client-side display mirror of `functions/src/lib/tiers.ts`'s `TIERS`
/// table (phase-07 §4) — copy, feature bullets, and StoreKit product ids
/// only. Never a source of truth for money: the actual price shown for a
/// paid tier must always come from that tier's `Product.displayPrice`
/// (localized, App-Store-authoritative) once StoreKit products load, never
/// from `referenceMonthlyFeeCents` here — that field exists purely so the
/// UI has *something* to show before StoreKit's product list has finished
/// loading, and for Free/Siltstone, which have no IAP product to ask.
struct TierInfo {
    let tier: Wallet.Tier
    let displayName: String
    let tagline: String
    /// `nil` for Free/Siltstone — neither is a StoreKit subscription.
    let productId: String?
    let referenceMonthlyFeeCents: Int
    let topUpBonusPercent: Int
    let lessonMinutes: Double
    let watermarked: Bool
    let downloadable: Bool
    let features: [String]

    static let topUpProductId = "com.shui.app.topup.5"

    static let all: [TierInfo] = [
        TierInfo(
            tier: .free,
            displayName: "Free",
            tagline: "One lesson on the house.",
            productId: nil,
            referenceMonthlyFeeCents: 0,
            topUpBonusPercent: 0,
            lessonMinutes: 0.5,
            watermarked: true,
            downloadable: false,
            features: ["One free 30-second lesson, ever", "Watermarked playback"]
        ),
        TierInfo(
            tier: .siltstone,
            displayName: "Siltstone",
            tagline: "Pay as you go — and the developer API's entry point.",
            productId: nil,
            referenceMonthlyFeeCents: 0,
            topUpBonusPercent: 0,
            lessonMinutes: 1,
            watermarked: true,
            downloadable: true,
            features: ["$4/min, pay only for what you generate", "1-minute lessons", "Downloadable (watermarked)", "Developer API access"]
        ),
        TierInfo(
            tier: .obsidian,
            displayName: "Obsidian",
            tagline: "A monthly credit with a top-up bonus.",
            productId: "com.shui.app.tier.obsidian.monthly",
            referenceMonthlyFeeCents: 2000,
            topUpBonusPercent: 10,
            lessonMinutes: 1,
            watermarked: true,
            downloadable: true,
            features: ["Monthly credit, unused balance rolls over", "10% bonus on every top-up", "1-minute lessons", "Downloadable (watermarked)"]
        ),
        TierInfo(
            tier: .alabaster,
            displayName: "Alabaster",
            tagline: "Clean downloads and social refunds.",
            productId: "com.shui.app.tier.alabaster.monthly",
            referenceMonthlyFeeCents: 5000,
            topUpBonusPercent: 15,
            lessonMinutes: 2,
            watermarked: false,
            downloadable: true,
            features: [
                "Monthly credit, unused balance rolls over", "15% bonus on every top-up", "2-minute lessons",
                "No watermark — clean downloads", "$2 credit refund per video that hits 100 likes (up to $20/cycle)",
            ]
        ),
        TierInfo(
            tier: .pyramidion,
            displayName: "Pyramidion",
            tagline: "Everything, plus API access on the same wallet.",
            productId: "com.shui.app.tier.pyramidion.monthly",
            referenceMonthlyFeeCents: 20000,
            topUpBonusPercent: 20,
            lessonMinutes: 2,
            watermarked: false,
            downloadable: true,
            features: [
                "Monthly credit, unused balance rolls over", "20% bonus on every top-up", "2-minute lessons",
                "No watermark — clean downloads", "$2 credit refund per 100 cumulative likes (up to $20/cycle)",
                "Developer API access on this same wallet", "Highest AI tutor usage cap",
            ]
        ),
    ]

    static func info(for tier: Wallet.Tier) -> TierInfo {
        all.first { $0.tier == tier } ?? all[0]
    }
}
