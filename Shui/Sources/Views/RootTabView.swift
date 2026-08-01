import SwiftUI

private enum RootTab: Hashable {
    case learn, explore, profile, debug
}

/// The three-tab shell. Learn is the real video feed as of Phase 2; Explore
/// and Profile are still placeholders until Phase 3.
struct RootTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var selection: RootTab = .learn

    var body: some View {
        TabView(selection: $selection) {
            FeedView(mode: .mixed, environment: environment, onExploreRequested: { selection = .explore })
                .tabItem { Label(Strings.learnTab, systemImage: "play.rectangle.fill") }
                .tag(RootTab.learn)
            ExploreView(environment: environment)
                .tabItem { Label(Strings.exploreTab, systemImage: "square.grid.2x2.fill") }
                .tag(RootTab.explore)
            ProfileView(environment: environment)
                .tabItem { Label(Strings.profileTab, systemImage: "person.crop.circle.fill") }
                .tag(RootTab.profile)
            #if DEBUG
            DebugUploadPipelineView()
                .tabItem { Label("Debug", systemImage: "ladybug.fill") }
                .tag(RootTab.debug)
            #endif
        }
        .tint(theme.accent)
    }
}

/// A launchable stub, not a mockup. Says which phase fills the tab in so an
/// empty screen never reads as a bug. Still used by pieces of Phase 3 and
/// later that haven't landed yet (e.g. Settings sub-screens).
struct PhasePlaceholderView: View {
    @Environment(\.theme) private var theme
    let title: String
    let phase: Int
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Coming in phase \(phase)")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shuiShellBackground()
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if appState.profile.hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingFlowView()
            }
        }
        // Runs in the background regardless of which branch above is
        // showing — onboarding's interests step needs a signed-in uid to
        // write to, and awaits this itself (idempotent) before saving, so
        // this doesn't need to block first paint.
        .task { await environment.bootstrapSession() }
        .onOpenURL { url in
            guard let link = DeepLink.parse(url) else { return }
            Task {
                // Guest-first still applies to a cold start from a link —
                // ensure a session exists before the destination screen
                // tries to read/write anything that needs one.
                await environment.bootstrapSession()
                appState.pendingDeepLink = link
            }
        }
        .fullScreenCover(item: $appState.pendingDeepLink) { link in
            DeepLinkContainer(link: link, environment: environment)
        }
    }
}
