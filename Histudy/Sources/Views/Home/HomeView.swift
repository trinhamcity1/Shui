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
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("\(appState.profile.currentStreak)")
                    .font(.title.bold())
                Text(L10n.homeStreakLabel.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.homeTodaysSession.localized)
                .font(.headline)

            if viewModel.plannedItemCount == 0 {
                Text(L10n.homeAllCaughtUp.localized)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: L10n.homeMinutesToday.localized, viewModel.estimatedMinutes))
                    .foregroundStyle(.secondary)

                Button(L10n.homeStartSession.localized) {
                    sessionItems = viewModel.buildSession(profile: appState.profile)
                    isPresentingSession = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
