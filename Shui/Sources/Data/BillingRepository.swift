import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

enum BillingError: LocalizedError {
    case notSignedIn
    case purchaseNotApplied
    case network
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to manage billing."
        case .purchaseNotApplied:
            return "Your purchase went through with Apple, but Shui couldn't apply it yet. It'll retry automatically — check back shortly."
        case .network:
            return "Couldn't reach Shui. Check your connection and try again."
        case .unknown(let message):
            return message
        }
    }
}

protocol BillingRepository {
    /// Live balance/tier updates — the billing screen's primary source, not
    /// a one-shot fetch, since a purchase, a lesson debit, or a like-refund
    /// can all change this while the screen is open.
    func observeWallet() -> AsyncThrowingStream<Wallet, Error>
    func wallet() async throws -> Wallet?
    /// Newest first, capped — the billing screen's history list, not a full
    /// export.
    func transactions(limit: Int) async throws -> [CreditTransaction]
    /// `signedTransactionInfo` is the raw JWS from StoreKit 2's
    /// `VerificationResult` — never a client-computed amount or product id.
    /// The App Store Server Notifications webhook is the durable backstop
    /// for this same purchase (phase-07 §4); this call is purely the fast
    /// path so the UI doesn't sit waiting on a webhook round trip.
    func applyPurchase(signedTransactionInfo: String) async throws -> (applied: Bool, tier: String?)
}

struct FirestoreBillingRepository: BillingRepository {
    private let db: Firestore
    private let functions: Functions
    private let auth: Auth

    init(
        db: Firestore = FirebaseBootstrap.firestore,
        functions: Functions = FirebaseBootstrap.functions,
        auth: Auth = FirebaseBootstrap.auth
    ) {
        self.db = db
        self.functions = functions
        self.auth = auth
    }

    private func walletRef(uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("private").document("wallet")
    }

    func observeWallet() -> AsyncThrowingStream<Wallet, Error> {
        AsyncThrowingStream { continuation in
            guard let uid = auth.currentUser?.uid else {
                continuation.finish(throwing: BillingError.notSignedIn)
                return
            }
            let registration = walletRef(uid: uid).addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let wallet = snapshot?.decodedIfExists(as: Wallet.self) else { return }
                continuation.yield(wallet)
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func wallet() async throws -> Wallet? {
        guard let uid = auth.currentUser?.uid else { throw BillingError.notSignedIn }
        return try await walletRef(uid: uid).getDocument().decodedIfExists()
    }

    func transactions(limit: Int) async throws -> [CreditTransaction] {
        guard let uid = auth.currentUser?.uid else { throw BillingError.notSignedIn }
        let snapshot = try await db.collection("users").document(uid).collection("creditTransactions")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.decoded()
    }

    func applyPurchase(signedTransactionInfo: String) async throws -> (applied: Bool, tier: String?) {
        do {
            let result = try await functions.httpsCallable("verifyAndApplyPurchase")
                .call(["signedTransactionInfo": signedTransactionInfo])
            guard let data = result.data as? [String: Any], let applied = data["applied"] as? Bool else {
                throw RepositoryError.malformedResponse
            }
            return (applied, data["tier"] as? String)
        } catch let error as NSError {
            guard error.domain == FunctionsErrorDomain else { throw BillingError.network }
            throw BillingError.unknown(error.localizedDescription)
        }
    }
}

final class InMemoryBillingRepository: BillingRepository {
    static let defaultWallet = Wallet(
        tier: .free,
        creditBalanceCents: 0,
        hasUsedFreeLesson: false,
        appAccountToken: "preview-token",
        appleOriginalTransactionId: nil,
        appleSubscriptionProductId: nil,
        likeRefundCentsThisCycle: 0,
        aiCycleStart: nil,
        aiCycleEnd: nil,
        aiSpentNanodollarsThisCycle: 0,
        cumulativeLikesReceived: 0,
        cumulativeLikesAccountedFor: 0
    )

    var walletValue: Wallet
    private var continuation: AsyncThrowingStream<Wallet, Error>.Continuation?

    init(wallet: Wallet = InMemoryBillingRepository.defaultWallet) {
        self.walletValue = wallet
    }

    func observeWallet() -> AsyncThrowingStream<Wallet, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(walletValue)
        }
    }

    func wallet() async throws -> Wallet? {
        walletValue
    }

    var transactionsValue: [CreditTransaction] = []

    func transactions(limit: Int) async throws -> [CreditTransaction] {
        Array(transactionsValue.prefix(limit))
    }

    func applyPurchase(signedTransactionInfo: String) async throws -> (applied: Bool, tier: String?) {
        (true, walletValue.tier.rawValue)
    }
}
