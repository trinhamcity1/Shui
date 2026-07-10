import SwiftUI

struct ProgressDashboardView: View {
    @StateObject private var viewModel = ProgressViewModel()
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        statTile(value: viewModel.overallMastered, label: L10n.progressMastered.localized, color: .green)
                        statTile(value: viewModel.overallLearning, label: L10n.progressLearning.localized, color: .orange)
                        statTile(value: viewModel.overallNew, label: L10n.progressNew.localized, color: .gray)
                    }
                    .listRowSeparator(.hidden)

                    HStack {
                        Text(L10n.progressCurrentStreak.localized)
                        Spacer()
                        Text("\(appState.profile.currentStreak)").bold()
                    }
                    HStack {
                        Text(L10n.progressLongestStreak.localized)
                        Spacer()
                        Text("\(appState.profile.longestStreak)").bold()
                    }
                }

                Section(L10n.progressCategoryBreakdown.localized) {
                    ForEach(viewModel.categorySummaries) { summary in
                        categoryRow(summary)
                    }
                }
            }
            .navigationTitle(L10n.progressTitle.localized)
            .onAppear { viewModel.load() }
        }
    }

    private func statTile(value: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryRow(_ summary: CategoryMasterySummary) -> some View {
        HStack {
            if let info = summary.info {
                Image(systemName: info.sfSymbol)
                    .foregroundStyle(Color.accentColor)
                Text(appState.profile.uiLanguage == .vietnamese ? info.nameVI : info.nameEN)
            }
            Spacer()
            Text("\(summary.mastered)/\(summary.total)")
                .foregroundStyle(.secondary)
        }
    }
}
