import SwiftUI

/// The three-tab shell. Each tab is a placeholder until its phase lands:
/// Learn is the video feed (Phase 2), Explore is categories and topics
/// (Phase 3), Profile is progress, likes, and settings (Phase 3).
struct RootTabView: View {
    var body: some View {
        TabView {
            PhasePlaceholderView(title: Strings.learnTab, phase: 2, detail: "The video feed lives here.")
                .tabItem { Label(Strings.learnTab, systemImage: "play.rectangle.fill") }
            PhasePlaceholderView(title: Strings.exploreTab, phase: 3, detail: "Categories and topics live here.")
                .tabItem { Label(Strings.exploreTab, systemImage: "square.grid.2x2.fill") }
            PhasePlaceholderView(title: Strings.profileTab, phase: 3, detail: "Progress, likes, and settings live here.")
                .tabItem { Label(Strings.profileTab, systemImage: "person.crop.circle.fill") }
            #if DEBUG
            DebugUploadPipelineView()
                .tabItem { Label("Debug", systemImage: "ladybug.fill") }
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
