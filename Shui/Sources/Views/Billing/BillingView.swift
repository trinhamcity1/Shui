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
    // Starts true, not false — `products` is also empty before the first
    // load even begins, and defaulting this to false would flash the
    // "Plans are unavailable" error banner for that split second instead of
    // a loading state.
    @Published private(set) var isLoadingProducts = true
    @Published private(set) var transactions: [CreditTransaction] = []
    @Published var errorMessage: String?
    @Published private(set) var purchasingProductId: String?
    @Published private(set) var isRestoring = false
    @Published var restoreMessage: String?

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

    /// A fresh anonymous sign-in's ID token can take a moment to propagate
    /// to the Firestore SDK — a listener attached in that exact window gets
    /// one permission-denied error even though the rules would otherwise
    /// allow it (this is the owner's own wallet). Firestore doesn't retry a
    /// permission error on its own the way it retries a network one, so a
    /// bounded retry here is what actually recovers from that race instead
    /// of leaving the balance blank for the rest of the session.
    private func observeWallet(attempt: Int = 0) {
        walletTask?.cancel()
        walletTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await value in self.environment.billing.observeWallet() {
                    self.wallet = value
                }
            } catch {
                guard !Task.isCancelled, attempt < 3 else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                self.observeWallet(attempt: attempt + 1)
            }
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
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
        guard let wallet else {
            errorMessage = "Still loading your account — try again in a moment."
            return
        }
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

    /// App Review requires a way to restore subscriptions. Syncs with the
    /// App Store, then re-sends each active subscription through the same
    /// server verification a purchase uses — a no-op for one already
    /// applied, and refused for one bought under a different Shui account
    /// (`appAccountToken`). Top-ups are consumables and never restore.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        var found = 0
        var firstFailure: String?
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified = entitlement else { continue }
            found += 1
            do {
                _ = try await environment.billing.applyPurchase(signedTransactionInfo: entitlement.jwsRepresentation)
            } catch {
                firstFailure = firstFailure ?? error.localizedDescription
            }
        }
        await loadTransactions()
        if let firstFailure {
            errorMessage = firstFailure
        } else {
            restoreMessage = found == 0 ? "No active subscription found for this Apple ID." : "Your subscription is restored."
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
                if viewModel.products.isEmpty {
                    productsUnavailableBanner
                }
                topUpSection
                plansSection
                subscriptionTerms
                historySection
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Balance & plan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            AppAnalytics.logFeatureTap(.openBilling)
            await viewModel.start()
        }
        .refreshable { await viewModel.loadProducts() }
        .onDisappear { viewModel.stop() }
        .shuiShellBackground()
        .alert("Something went wrong", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button(Strings.done, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Restore purchases", isPresented: Binding(get: { viewModel.restoreMessage != nil }, set: { if !$0 { viewModel.restoreMessage = nil } })) {
            Button(Strings.done, role: .cancel) {}
        } message: {
            Text(viewModel.restoreMessage ?? "")
        }
    }

    /// What App Review requires next to anything sold as an auto-renewing
    /// subscription: how renewal and cancellation work, links to the terms
    /// and privacy policy, and a way to restore a past purchase.
    private var subscriptionTerms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await viewModel.restorePurchases() }
            } label: {
                HStack {
                    Text("Restore purchases")
                    Spacer()
                    if viewModel.isRestoring {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.shuiPillOutline)
            .disabled(viewModel.isRestoring || viewModel.purchasingProductId != nil)

            Text("Plans are monthly subscriptions that renew automatically at the price shown until canceled. Payment is charged to your Apple ID. Cancel at least 24 hours before the period ends in Settings › your name › Subscriptions.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 16) {
                if let url = LegalLinks.termsOfService {
                    Link("Terms of Service", destination: url)
                }
                if let url = LegalLinks.privacyPolicy {
                    Link("Privacy Policy", destination: url)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 20)
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

    /// StoreKit's product list can legitimately come back empty — a brand
    /// new App Store Connect setup still propagating, a sandbox hiccup, a
    /// real network drop — and without this, `topUpSection`/`plansSection`
    /// would just quietly render nothing, which reads as "this app has no
    /// way to pay" rather than "try again."
    @ViewBuilder
    private var productsUnavailableBanner: some View {
        HStack(spacing: 12) {
            if viewModel.isLoadingProducts {
                ProgressView()
                Text("Loading plans…")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plans are unavailable right now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Pull to refresh, or try again in a moment.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Retry") { Task { await viewModel.loadProducts() } }
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shuiCard()
        .padding(.horizontal, 20)
    }

    /// phase-07 §4's own tier table marks "Min deposit / top-up" as "—" for
    /// Free — top-up is a paid-tier mechanic (it tops up a credit balance
    /// that spends down a subscription's Siltstone/Obsidian/etc. `timing`
    /// rules), not something a Free account, which gets exactly one free
    /// lesson and no ongoing balance, has a use for.
    @ViewBuilder
    private var topUpSection: some View {
        if viewModel.wallet?.tier != .free, let topUpProduct = viewModel.product(for: TierInfo.topUpProductId) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top up").font(.title3.bold()).foregroundStyle(theme.textPrimary).padding(.horizontal, 20)
                Button {
                    AppAnalytics.logFeatureTap(.topUp)
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
                    AppAnalytics.logFeatureTap(.subscribe)
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
