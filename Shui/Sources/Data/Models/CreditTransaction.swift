import FirebaseFirestore
import Foundation

/// Mirrors one row of `users/{uid}/creditTransactions` — the append-only
/// ledger every wallet mutation writes alongside itself (`writeLedgerRow` in
/// `functions/src/lib/credits.ts`). The billing screen's transaction history
/// reads this directly rather than trying to reconstruct history from the
/// wallet's current balance.
struct CreditTransaction: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case topup
        case subscriptionGrant = "subscription_grant"
        case lessonDebit = "lesson_debit"
        case lessonRefund = "lesson_refund"
        case likeRefund = "like_refund"
        case freeGrant = "free_grant"
    }

    @DocumentID var id: String?
    var type: Kind
    /// Signed — negative for a debit, positive for a credit, matching the
    /// server's own convention exactly (never re-signed client-side).
    var amountCents: Int
    var relatedVideoId: String?
    var relatedAppleTransactionId: String?
    var note: String?
    var createdAt: Date?

    var displayTitle: String {
        switch type {
        case .topup: return "Top-up"
        case .subscriptionGrant: return "Subscription credit"
        case .lessonDebit: return "Lesson generated"
        case .lessonRefund: return "Lesson refund"
        case .likeRefund: return "Like refund"
        case .freeGrant: return "Free lesson"
        }
    }

    var amountDisplay: String {
        let magnitude = (Double(abs(amountCents)) / 100).formatted(.currency(code: "USD"))
        return amountCents < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
