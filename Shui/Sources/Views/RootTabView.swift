import SwiftUI

/// The three-tab shell. Social (phase-07 §6) is the primary scrolling feed —
/// on-demand lessons ranked by reference — replacing the old composed
/// Learn feed in that slot.
struct RootTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var appState: AppState
    @Environment(\.theme) private var theme
    /// `TabView`'s own selection binding deliberately stays local `@State`
    /// — the same way it worked before swipe navigation existed — rather
    /// than binding directly to `appState.rootTab`. Routing `TabView`
    /// straight through an `@EnvironmentObject`-sourced `@Published`
    /// property is the leading suspect for a real regression: the tab bar
    /// stopped reliably hiding during the very first autoplay after a
    /// genuine cold launch (backgrounding/foregrounding was unaffected,
    /// and this is the only thing that changed in this area since it last
    /// worked). `appState.rootTab` stays the single source of truth swipe
    /// gestures read and write — reachable from screens pushed deep inside
    /// Explore/Profile, which local `@State` here never could be — synced
    /// both directions below so tapping a tab icon and swiping can never
    /// drift out of step with each other.
    @State private var selection: RootTab = .social

    var body: some View {
        TabView(selection: $selection) {
            SocialFeedView(environment: environment)
                .tabItem { Label(Strings.socialTab, systemImage: "sparkles.tv.fill") }
                .tag(RootTab.social)
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
        .onChange(of: appState.rootTab) { _, newValue in
            if selection != newValue { selection = newValue }
        }
        .onChange(of: selection) { _, newValue in
            if appState.rootTab != newValue { appState.rootTab = newValue }
        }
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
    @Environment(\.scenePhase) private var scenePhase

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
        // Re-mint the ID token on every foreground so a role granted from
        // the admin surface (or the Firebase console) shows up without a
        // reinstall — custom claims are fixed at mint time, so a cached
        // token would keep reporting the old role for up to an hour.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await environment.refreshRole(forceRefresh: true) }
        }
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
