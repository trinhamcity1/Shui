import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label(L10n.homeTabHome.localized, systemImage: "house.fill") }
            ProgressDashboardView()
                .tabItem { Label(L10n.homeTabProgress.localized, systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label(L10n.homeTabSettings.localized, systemImage: "gearshape.fill") }
        }
    }
}

/// Decides between the first-run onboarding flow and the main tab bar,
/// re-created (via `.id`) whenever the UI language changes so every screen
/// picks up the newly selected `Localizable.strings` bundle.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        Group {
            if appState.profile.hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .id(localization.currentLanguage)
    }
}
