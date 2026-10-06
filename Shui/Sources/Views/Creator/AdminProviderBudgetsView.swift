import SwiftUI

/// Admin-only view of GolpoAI's balance (phase-08 provider-budget
/// tracking). Read straight from their own `/users/credits` API, cached a
/// few minutes server-side — purely informational, no admin action needed.
/// Anthropic spend isn't tracked here at all: their API has no equivalent
/// balance endpoint, so Anthropic's own account-level spending limit and
/// email alerts (set directly in their console) are the safety net for
/// that provider instead. See `functions/src/lib/providerBudgets.ts`.
struct AdminProviderBudgetsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var page: ProviderBudgetsPage?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                        budgetRowContent(budget)
                    }
                } header: {
                    Text("Tracked balances")
                } footer: {
                    Text("Read live from GolpoAI's own API — nothing to maintain here.")
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
    }

    private func budgetRowContent(_ budget: ProviderBudgetInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(budget.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary)
                Spacer()
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                if budget.alertActive {
                    Label("Low", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.warning)
                }
            }
            Text(currency(budget.remainingCents) + " remaining")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(budget.alertActive ? theme.warning : theme.textPrimary)
            Text("Cached a few minutes · alert under \(currency(budget.lowBalanceThresholdCents))")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
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
