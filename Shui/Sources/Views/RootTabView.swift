import SwiftUI

/// The three-tab shell. Learn is the real video feed as of Phase 2; Explore
/// and Profile are still placeholders until Phase 3.
///
/// Not a `TabView` — a custom pager. `TabView` can't show two tabs' content
/// at once, which is exactly what a real Instagram-style peek during a
/// ring swipe needs (the destination tab visible at the edge, sliding in
/// with the finger, not just decided and jumped to on release). All three
/// ring tabs stay instantiated simultaneously as siblings in one `HStack`
/// — the same "every tab keeps its own live state" behavior `TabView`
/// already gave for free — offset by `-index * width`, plus
/// `appState.rootDragOffset` while `RootRingPeekSwipe` (attached to each
/// tab's own root content) is tracking an active drag.
struct RootTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var appState: AppState
    @Environment(\.theme) private var theme
    /// Debug isn't part of the ring — it replaces the whole screen rather
    /// than taking a slot next to Learn/Explore/Profile, so it's tracked
    /// separately from `appState.rootTab` entirely.
    @State private var isShowingDebug = false

    var body: some View {
        Group {
            #if DEBUG
            if isShowingDebug {
                DebugUploadPipelineView()
            } else {
                pager
            }
            #else
            pager
            #endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !appState.isTabBarHidden {
                tabBar
            }
        }
    }

    private var pager: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let index = RootTab.ring.firstIndex(of: appState.rootTab) ?? 0
            HStack(spacing: 0) {
                FeedView(mode: .mixed, environment: environment, onExploreRequested: { appState.rootTab = .explore })
                    .frame(width: width, height: geo.size.height)
                ExploreView(environment: environment)
                    .frame(width: width, height: geo.size.height)
                ProfileView(environment: environment)
                    .frame(width: width, height: geo.size.height)
            }
            .offset(x: -CGFloat(index) * width + appState.rootDragOffset)
        }
        .clipped()
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabBarButton(tab: .learn, label: Strings.learnTab, systemImage: "play.rectangle.fill")
            tabBarButton(tab: .explore, label: Strings.exploreTab, systemImage: "square.grid.2x2.fill")
            tabBarButton(tab: .profile, label: Strings.profileTab, systemImage: "person.crop.circle.fill")
            #if DEBUG
            debugTabBarButton
            #endif
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabBarButton(tab: RootTab, label: String, systemImage: String) -> some View {
        let isSelected = !isShowingDebug && appState.rootTab == tab
        return Button {
            isShowingDebug = false
            withAnimation(.easeOut(duration: 0.28)) {
                appState.rootTab = tab
                appState.rootDragOffset = 0
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.system(size: 22))
                Text(label).font(.caption2)
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    #if DEBUG
    private var debugTabBarButton: some View {
        Button {
            isShowingDebug = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "ladybug.fill").font(.system(size: 22))
                Text("Debug").font(.caption2)
            }
            .foregroundStyle(isShowingDebug ? theme.accent : theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Debug")
        .accessibilityAddTraits(isShowingDebug ? [.isSelected] : [])
    }
    #endif
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
