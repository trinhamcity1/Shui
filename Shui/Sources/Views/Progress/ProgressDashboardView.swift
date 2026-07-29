import SwiftUI

struct ProgressDashboardView: View {
    @StateObject private var viewModel = ProgressViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var showingUpgrade = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        statTile(value: viewModel.overallMastered, label: L10n.progressMastered.localized, color: .green)
                        statTile(value: viewModel.overallLearning, label: L10n.progressLearning.localized, color: Theme.shell.gradientStart)
                        statTile(value: viewModel.overallNew, label: L10n.progressNew.localized, color: Theme.shell.metadata)
                    }
                    .listRowSeparator(.hidden)

                    HStack {
                        Text(L10n.progressCurrentStreak.localized)
                            .foregroundStyle(Theme.shell.ink)
                        Spacer()
                        Text("\(appState.profile.currentStreak)")
                            .bold()
                            .foregroundStyle(Theme.shell.ink)
                    }
                    HStack {
                        Text(L10n.progressLongestStreak.localized)
                            .foregroundStyle(Theme.shell.ink)
                        Spacer()
                        Text("\(appState.profile.longestStreak)")
                            .bold()
                            .foregroundStyle(Theme.shell.ink)
                    }
                }
                .listRowBackground(Color.white)

                Section(L10n.progressCategoryBreakdown.localized) {
                    ForEach(viewModel.categorySummaries) { summary in
                        categoryRow(summary)
                    }
                }
                .listRowBackground(Color.white)

                Section(L10n.analyticsTitle.localized) {
                    if appState.profile.isPro {
                        ForEach(viewModel.categorySummaries) { summary in
                            accuracyRow(summary)
                        }
                    } else {
                        analyticsLockedRow
                    }
                }
                .listRowBackground(Color.white)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .shuiShellBackground()
            .navigationTitle(L10n.progressTitle.localized)
            .onAppear { viewModel.load() }
            .sheet(isPresented: $showingUpgrade) {
                UpgradePromptView()
            }
        }
    }

    private func statTile(value: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.shell.metadata)
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryRow(_ summary: CategoryMasterySummary) -> some View {
        HStack {
            if let info = summary.info {
                Image(systemName: info.sfSymbol)
                    .foregroundStyle(Theme.shell.gradientStart)
                Text(appState.profile.uiLanguage == .vietnamese ? info.nameVI : info.nameEN)
                    .foregroundStyle(Theme.shell.ink)
            }
            Spacer()
            Text("\(summary.mastered)/\(summary.total)")
                .foregroundStyle(Theme.shell.metadata)
        }
    }

    private func accuracyRow(_ summary: CategoryMasterySummary) -> some View {
        HStack {
            if let info = summary.info {
                Text(appState.profile.uiLanguage == .vietnamese ? info.nameVI : info.nameEN)
                    .foregroundStyle(Theme.shell.ink)
            }
            Spacer()
            Text(summary.accuracyLabel)
                .bold()
                .foregroundStyle(Theme.shell.ink)
        }
    }

    private var analyticsLockedRow: some View {
        Button {
            showingUpgrade = true
        } label: {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.shell.gradientEnd)
                Text(L10n.analyticsLocked.localized)
                    .foregroundStyle(Theme.shell.metadata)
                Spacer()
                Text(L10n.proBadge.localized)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.shell.accentGradient, in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}
