import SwiftUI

/// Admin-only view of Shui's own self-tracked GolpoAI/Anthropic spend
/// (phase-08 provider-budget tracking). Neither provider exposes a live
/// balance API, so "remaining" here is only as accurate as the last time an
/// admin recorded a real top-up here after topping up on the provider's own
/// dashboard — see `functions/src/lib/providerBudgets.ts`.
struct AdminProviderBudgetsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var page: ProviderBudgetsPage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var topUpTarget: ProviderBudgetInfo?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).font(.subheadline).foregroundStyle(theme.error) }
            }

            if let page {
                if !page.openAlerts.isEmpty {
                    Section {
                        ForEach(page.openAlerts) { alert in
                            alertRow(alert)
                        }
                    } header: {
                        Text("Open alerts")
                    }
                }

                Section {
                    ForEach(page.budgets) { budget in
                        budgetRow(budget)
                    }
                } header: {
                    Text("Tracked balances")
                } footer: {
                    Text("Self-tracked, not live — record a top-up here every time one happens on GolpoAI's or Anthropic's own dashboard, or this drifts from reality.")
                }
            } else if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Provider budgets")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $topUpTarget, onDismiss: { Task { await load() } }) { budget in
            RecordTopUpSheet(environment: environment, budget: budget)
        }
    }

    private func budgetRow(_ budget: ProviderBudgetInfo) -> some View {
        Button { topUpTarget = budget } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(budget.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Spacer()
                    if budget.alertActive {
                        Label("Low", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(theme.warning)
                    }
                }
                Text(currency(budget.remainingCents) + " remaining")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(budget.alertActive ? theme.warning : theme.textPrimary)
                Text("\(currency(budget.toppedUpCentsAllTime)) topped up · \(currency(budget.spentCentsAllTime)) spent · alert under \(currency(budget.lowBalanceThresholdCents))")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func alertRow(_ alert: AdminAlertInfo) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.type == "provider_budget_exhausted" ? "\(alert.provider.capitalized) is exhausted" : "\(alert.provider.capitalized) balance is low")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.error)
                Text("\(currency(alert.remainingCents)) remaining, threshold \(currency(alert.thresholdCents))")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Button("Dismiss") { Task { await acknowledge(alert) } }
                .font(.caption)
        }
    }

    private func currency(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD"))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            page = try await environment.admin.providerBudgets()
        } catch {
            errorMessage = "Couldn't load provider budgets."
        }
    }

    private func acknowledge(_ alert: AdminAlertInfo) async {
        do {
            try await environment.admin.acknowledgeAlert(alertId: alert.alertId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecordTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let environment: AppEnvironment
    let budget: ProviderBudgetInfo

    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var amountCents: Int? {
        guard let dollars = Double(amountText), dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount just topped up on \(budget.displayName)'s own dashboard") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.subheadline).foregroundStyle(theme.error) }
                }
            }
            .navigationTitle("Record top-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.save) { Task { await save() } }
                        .disabled(amountCents == nil || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let amountCents else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await environment.admin.recordProviderTopUp(provider: budget.provider, amountCents: amountCents)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
