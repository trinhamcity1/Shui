import SwiftUI

/// `shui://video/{id}` and `shui://topic/{id}` — the two links Phase 2's
/// `ShareLink` already produces. Anything else parses to `nil` rather than
/// guessing at a fallback destination.
enum DeepLink: Identifiable, Equatable {
    case video(id: String)
    case topic(id: String)

    var id: String {
        switch self {
        case .video(let id): return "video-\(id)"
        case .topic(let id): return "topic-\(id)"
        }
    }

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "shui", let kind = url.host else { return nil }
        guard let id = url.pathComponents.first(where: { $0 != "/" }) else { return nil }
        switch kind {
        case "video": return .video(id: id)
        case "topic": return .topic(id: id)
        default: return nil
        }
    }
}

/// Presented as a full-screen cover from the app root, independent of
/// whatever tab/navigation state already exists — the simplest correct way
/// to land on the right screen from a cold start without threading
/// deep-link state through every tab's own NavigationStack.
struct DeepLinkContainer: View {
    let link: DeepLink
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch link {
        case .video(let id):
            DeepLinkVideoLoader(videoId: id, environment: environment)
        case .topic(let id):
            TopicPageView(topicId: id, environment: environment)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        DismissButton()
                    }
                }
        }
    }
}

/// `FeedView` for a single video — reuses `.videoList` mode (built for the
/// Profile tab's liked-videos and review feeds) rather than a fourth mode
/// just for this. `FeedPageView`'s own back chevron (shown whenever
/// `topicModeInfo` is non-nil, which a one-item videoList satisfies) is
/// this screen's close affordance — `FeedView` hides the system nav bar
/// unconditionally, so a toolbar button here would never actually show.
private struct DeepLinkVideoLoader: View {
    let videoId: String
    let environment: AppEnvironment
    @State private var video: Video?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                FeedErrorStateView(message: loadError, onRetry: { Task { await load() } })
            } else if let video {
                FeedView(mode: .videoList(videos: [video]), environment: environment)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        guard let fetched = try? await environment.videos.video(id: videoId) else {
            loadError = "This video couldn't be found."
            return
        }
        video = fetched
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(Strings.cancel) { dismiss() }
    }
}
