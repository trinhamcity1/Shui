import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = HomeViewModel()
    @State private var sessionItems: [SessionItem] = []
    @State private var isPresentingSession = false

    private var language: AppLanguage { appState.profile.uiLanguage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let greeting = viewModel.greeting {
                        TutorSpeechView(message: greeting, language: language)
                    }
                    streakCard
                    sessionCard
                }
                .padding()
            }
            .shuiShellBackground()
            .navigationTitle(L10n.appName.localized)
            .task { await viewModel.load(profile: appState.profile) }
            .navigationDestination(isPresented: $isPresentingSession) {
                SessionFlowView(items: sessionItems, appState: appState)
            }
        }
    }

    private var streakCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(Theme.shell.gradientStart)
            VStack(alignment: .leading) {
                Text("\(appState.profile.currentStreak)")
                    .font(.title.bold())
                    .foregroundStyle(Theme.shell.ink)
                Text(L10n.homeStreakLabel.localized)
                    .font(.caption)
                    .foregroundStyle(Theme.shell.metadata)
            }
            Spacer()
        }
        .shuiCard()
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.homeTodaysSession.localized)
                .font(.headline)
                .foregroundStyle(Theme.shell.ink)

            if viewModel.plannedItemCount == 0 {
                Text(L10n.homeAllCaughtUp.localized)
                    .foregroundStyle(Theme.shell.metadata)
            } else {
                Text(String(format: L10n.homeMinutesToday.localized, viewModel.estimatedMinutes))
                    .foregroundStyle(Theme.shell.metadata)

                Button(L10n.homeStartSession.localized) {
                    sessionItems = viewModel.buildSession(profile: appState.profile)
                    isPresentingSession = true
                }
                .buttonStyle(.shuiPill)
            }
        }
        .shuiCard()
    }
}
