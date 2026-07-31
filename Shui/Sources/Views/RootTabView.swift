import SwiftUI

private enum RootTab: Hashable {
    case learn, explore, profile, debug
}

/// The three-tab shell. Learn is the real video feed as of Phase 2; Explore
/// and Profile are still placeholders until Phase 3.
struct RootTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selection: RootTab = .learn

    var body: some View {
        TabView(selection: $selection) {
            FeedView(mode: .mixed, environment: environment, onExploreRequested: { selection = .explore })
                .tabItem { Label(Strings.learnTab, systemImage: "play.rectangle.fill") }
                .tag(RootTab.learn)
            PhasePlaceholderView(title: Strings.exploreTab, phase: 3, detail: "Categories and topics live here.")
                .tabItem { Label(Strings.exploreTab, systemImage: "square.grid.2x2.fill") }
                .tag(RootTab.explore)
            PhasePlaceholderView(title: Strings.profileTab, phase: 3, detail: "Progress, likes, and settings live here.")
                .tabItem { Label(Strings.profileTab, systemImage: "person.crop.circle.fill") }
                .tag(RootTab.profile)
            #if DEBUG
            DebugUploadPipelineView()
                .tabItem { Label("Debug", systemImage: "ladybug.fill") }
                .tag(RootTab.debug)
            #endif
        }
        .tint(Theme.shell.gradientStart)
    }
}

/// A launchable stub, not a mockup. Says which phase fills the tab in so an
/// empty screen never reads as a bug.
struct PhasePlaceholderView: View {
    let title: String
    let phase: Int
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Coming in phase \(phase)")
                .font(.headline)
                .foregroundStyle(Theme.shell.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.metadata)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shuiShellBackground()
    }
}

struct RootView: View {
    var body: some View {
        RootTabView()
    }
}
