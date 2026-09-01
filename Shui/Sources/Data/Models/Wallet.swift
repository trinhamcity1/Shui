import FirebaseFirestore
import Foundation

/// Mirrors `users/{uid}/private/wallet` (phase-07 §1/§4) — deliberately not a
/// subcollection of the public `users/{uid}` doc, and deliberately not
/// cached in SwiftData: this is server-authoritative money, always read
/// live, never computed or stored client-side. Rules make this owner-read,
/// Function-write-only — see `firestore.rules`.
struct Wallet: Codable, Hashable {
    enum Tier: String, Codable, CaseIterable {
        case free, siltstone, obsidian, alabaster, pyramidion
    }

    var tier: Tier
    var creditBalanceCents: Int
    var hasUsedFreeLesson: Bool
    /// StoreKit's `appAccountToken` for this account — the client reads this
    /// back to pass into `Product.PurchaseOption.appAccountToken` on every
    /// purchase, never generates its own (the server mints it once at
    /// account creation).
    var appAccountToken: String
    var appleOriginalTransactionId: String?
    var appleSubscriptionProductId: String?
    var likeRefundCentsThisCycle: Int
    var aiCycleStart: Date?
    var aiCycleEnd: Date?
    var aiSpentNanodollarsThisCycle: Int
    var cumulativeLikesReceived: Int
    var cumulativeLikesAccountedFor: Int

    var creditBalanceDisplay: String {
        (Double(creditBalanceCents) / 100).formatted(.currency(code: "USD"))
    }
}
