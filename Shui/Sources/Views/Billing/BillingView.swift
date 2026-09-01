import StoreKit
import SwiftUI

enum BillingScreenError: LocalizedError {
    case invalidAccountToken
    case verificationFailed
    case pending
    case other(String)

    var errorDescription: String? {
        switch self {
        case .invalidAccountToken:
            return "Couldn't start checkout — try again in a moment."
        case .verificationFailed:
            return "Apple couldn't verify this purchase."
        case .pending:
            return "Your purchase needs approval (e.g. Ask to Buy) before it completes."
        case .other(let message):
            return message
        }
    }
}

@MainActor
final class BillingViewModel: ObservableObject {
    @Published private(set) var wallet: Wallet?
    @Published private(set) var products: [Product] = []
    @Published private(set) var transactions: [CreditTransaction] = []
    @Published var errorMessage: String?
    @Published private(set) var purchasingProductId: String?

    private let environment: AppEnvironment
    private var walletTask: Task<Void, Never>?
    // Scoped to this screen's lifetime, not app launch — a purchase that
    // finishes while the learner isn't on this screen is still applied by
    // the App Store Server Notifications webhook (the documented durable
    // backstop, see functions/src/webhooks/appStoreServerNotifications.ts);
    // this listener is purely the fast path for the common case of
    // completing a purchase while watching this screen.
    private var transactionListener: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func start() async {
        observeWallet()
        listenForTransactionUpdates()
        async let productsLoad: Void = loadProducts()
        async let transactionsLoad: Void = loadTransactions()
        _ = await (productsLoad, transactionsLoad)
    }

    func stop() {
        walletTask?.cancel()
        transactionListener?.cancel()
    }

    private func observeWallet() {
        walletTask?.cancel()
        walletTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await value in self.environment.billing.observeWallet() {
                    self.wallet = value
                }
            } catch {
                // Leave the last known wallet value on screen rather than
                // clearing it out from under the learner over a transient
                // listener error.
            }
        }
    }

    private func loadProducts() async {
        let ids = TierInfo.all.compactMap(\.productId) + [TierInfo.topUpProductId]
        products = (try? await Product.products(for: ids)) ?? []
    }

    func loadTransactions() async {
        transactions = (try? await environment.billing.transactions(limit: 50)) ?? []
    }

    private func listenForTransactionUpdates() {
        transactionListener?.cancel()
        transactionListener = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.apply(update)
            }
        }
    }

    func product(for productId: String) -> Product? {
        products.first { $0.id == productId }
    }

    func purchase(_ product: Product) async {
        guard let wallet else { return }
        guard let token = UUID(uuidString: wallet.appAccountToken) else {
            errorMessage = BillingScreenError.invalidAccountToken.localizedDescription
            return
        }
        purchasingProductId = product.id
        defer { purchasingProductId = nil }
        do {
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                await apply(verification)
            case .userCancelled:
                break
            case .pending:
                errorMessage = BillingScreenError.pending.localizedDescription
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification else {
            errorMessage = BillingScreenError.verificationFailed.localizedDescription
            return
        }
        do {
            _ = try await environment.billing.applyPurchase(signedTransactionInfo: verification.jwsRepresentation)
            await transaction.finish()
            await loadTransactions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// phase-07 §9 — current tier, credit balance, top-up, subscribe/change
/// tier, transaction history. Every dollar figure for a paid tier comes
/// from `Product.displayPrice` once StoreKit's product list loads — never
/// `TierInfo.referenceMonthlyFeeCents`, which exists only as a
/// before-StoreKit-loads placeholder.
struct BillingView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: BillingViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: BillingViewModel(environment: environment))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                balanceCard
                topUpSection
                plansSection
                historySection
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Balance & plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .shuiShellBackground()
        .alert("Something went wrong", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button(Strings.done, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current plan").font(.caption).foregroundStyle(theme.textSecondary)
            Text(TierInfo.info(for: viewModel.wallet?.tier ?? .free).displayName)
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
            Text(viewModel.wallet?.creditBalanceDisplay ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("credit balance")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shuiCard()
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var topUpSection: some View {
        if let topUpProduct = viewModel.product(for: TierInfo.topUpProductId) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top up").font(.title3.bold()).foregroundStyle(theme.textPrimary).padding(.horizontal, 20)
                Button {
                    Task { await viewModel.purchase(topUpProduct) }
                } label: {
                    HStack {
                        Text("Add \(topUpProduct.displayPrice) of credit")
                        Spacer()
                        if viewModel.purchasingProductId == topUpProduct.id {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.shuiPillOutline)
                .disabled(viewModel.purchasingProductId != nil)
                .padding(.horizontal, 20)
            }
        }
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plans").font(.title3.bold()).foregroundStyle(theme.textPrimary).padding(.horizontal, 20)
            VStack(spacing: 12) {
                ForEach(TierInfo.all, id: \.tier) { info in
                    planCard(info)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func planCard(_ info: TierInfo) -> some View {
        let isCurrent = viewModel.wallet?.tier == info.tier
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.displayName).font(.headline).foregroundStyle(theme.textPrimary)
                    Text(info.tagline).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if let productId = info.productId, let product = viewModel.product(for: productId) {
                    Text("\(product.displayPrice)/mo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            ForEach(info.features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            if isCurrent {
                Text("Current plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.success)
                    .padding(.top, 4)
            } else if let productId = info.productId, let product = viewModel.product(for: productId) {
                Button {
                    Task { await viewModel.purchase(product) }
                } label: {
                    HStack {
                        Text("Switch to \(info.displayName)")
                        Spacer()
                        if viewModel.purchasingProductId == product.id {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.shuiPill)
                .disabled(viewModel.purchasingProductId != nil)
                .padding(.top, 4)
            }
        }
        .shuiCard()
    }

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.transactions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent activity").font(.title3.bold()).foregroundStyle(theme.textPrimary).padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(viewModel.transactions) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transaction.displayTitle).font(.subheadline).foregroundStyle(theme.textPrimary)
                                if let createdAt = transaction.createdAt {
                                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                            Spacer()
                            Text(transaction.amountDisplay)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(transaction.amountCents >= 0 ? theme.success : theme.textSecondary)
                        }
                        .padding(.vertical, 8)
                        if transaction.id != viewModel.transactions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
