import SwiftUI

/// One full-bleed page of the feed: video, overlays, right rail, and the
/// quiz card that slides up once the video ends.
struct FeedPageView: View {
    @ObservedObject var viewModel: FeedViewModel
    @ObservedObject var page: FeedPageViewModel
    let index: Int
    let onNextLesson: () -> Void
    let onRequireSignIn: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var showPauseGlyph = false
    @State private var showInfoSheet = false
    @State private var showCommentsPlaceholder = false
    @State private var showAIPlaceholder = false

    private var playbackState: PlaybackState { viewModel.playerPool.states[index] ?? .idle }
    private var progress: Double { viewModel.playerPool.progress[index] ?? 0 }

    var body: some View {
        ZStack {
            Color.black

            if let player = viewModel.playerPool.player(forIndex: index) {
                VideoPlayerLayerView(player: player)
                    .accessibilityHidden(true)
            }

            statusOverlay

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomOverlay
            }

            if showPauseGlyph {
                Image(systemName: "play.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.9))
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            QuizOverlayContainer(
                page: page,
                viewModel: viewModel,
                reduceMotion: reduceMotion,
                onNextLesson: onNextLesson
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard page.endState == .notEnded else { return }
            viewModel.playerPool.togglePlayPause(index: index)
        }
        .onChange(of: playbackState) { _, newValue in
            handlePlaybackStateChange(newValue)
        }
        .sheet(isPresented: $showInfoSheet) {
            VideoInfoSheet(video: page.video)
        }
        .sheet(isPresented: $showCommentsPlaceholder) {
            ComingSoonSheet(title: "Comments", phase: 3, detail: "Comment threads live here.")
        }
        .sheet(isPresented: $showAIPlaceholder) {
            ComingSoonSheet(title: "AI Tutor", phase: 4, detail: "A grounded chat about this lesson lives here.")
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch playbackState {
        case .failed:
            FailureCard(title: page.video.title) { retryLoad() }
        case .loading, .idle:
            ProgressView().tint(.white)
        default:
            EmptyView()
        }
    }

    private func retryLoad() {
        guard let url = URL(string: page.video.playbackURL) else { return }
        viewModel.playerPool.prepare(index: index, url: url, window: index...index)
        viewModel.playerPool.activate(index: index)
    }

    private func handlePlaybackStateChange(_ newValue: PlaybackState) {
        switch newValue {
        case .paused:
            showPauseGlyph = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                if playbackState == .paused {
                    withAnimation { showPauseGlyph = false }
                }
            }
        case .failed:
            showPauseGlyph = false
            AppAnalytics.logVideoLoadFailed(videoId: page.video.id ?? "unknown")
        default:
            showPauseGlyph = false
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)

            if let topicInfo = viewModel.topicModeInfo {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")

                    Spacer()

                    Text("\(topicInfo.index) of \(topicInfo.total)")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.4)))
                        .foregroundStyle(.white)

                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.top, 8)
    }

    private var bottomOverlay: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Button { showInfoSheet = true } label: {
                    Text(page.video.topicTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

                Text(page.video.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if !page.video.description.isEmpty {
                    Text(page.video.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                    Button("more") { showInfoSheet = true }
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The video overlay caption caps out earlier than the quiz card
            // (which supports Dynamic Type up to XL) — there's only so much
            // room over a full-bleed video before text swallows the frame.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)

            FeedRightRail(
                page: page,
                isGuest: environment.isGuest,
                onLike: { viewModel.toggleLike(for: page) },
                onComments: { showCommentsPlaceholder = true },
                onAITutor: { showAIPlaceholder = true },
                onRequireSignIn: onRequireSignIn
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

/// Shown in place of the video when playback fails — never a black screen.
struct FailureCard: View {
    let title: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.white)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("This video couldn't load.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Button("Retry", action: onRetry)
                .buttonStyle(.shuiPill)
        }
        .padding(28)
    }
}
