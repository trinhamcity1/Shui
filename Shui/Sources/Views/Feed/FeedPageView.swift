import SwiftUI

/// One full-bleed page of the feed: video, overlays, right rail, and the
/// quiz card that slides up once the video ends.
struct FeedPageView: View {
    @ObservedObject var viewModel: FeedViewModel
    @ObservedObject var page: FeedPageViewModel
    let index: Int
    let onNextLesson: () -> Void
    let onRequireSignIn: () -> Void
    /// The real, tab-bar-inclusive bottom safe area inset, captured above
    /// `FeedView`'s `.ignoresSafeArea()` — see that file for why this can't
    /// just be read locally via `@Environment`. Used only to keep the quiz
    /// card's buttons clear of the tab bar; this page's own frame stays
    /// full screen height regardless, which is what keeps paging correct.
    let tabBarBottomInset: CGFloat

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPauseGlyph = false
    @State private var isCaptionExpanded = false
    @State private var showComments = false
    @State private var showAITutor = false
    @State private var wasPlayingBeforeAITutor = false

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
                onNextLesson: onNextLesson,
                tabBarBottomInset: tabBarBottomInset
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
        .sheet(isPresented: $showComments) {
            CommentsSheet(videoId: page.video.id ?? "", initialCommentCount: page.commentCount, environment: environment)
        }
        .sheet(
            isPresented: $showAITutor,
            onDismiss: {
                if wasPlayingBeforeAITutor {
                    viewModel.playerPool.togglePlayPause(index: index)
                }
            },
            content: {
                AITutorSheet(videoId: page.video.id ?? "", environment: environment)
            }
        )
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

            // No back button — this feed is left purely to the swipe
            // gesture (`FeedView`'s `.ringSwipeNavigation`) now, matching
            // the fully gestural, no-chrome feel a full-bleed video wants.
            if let topicInfo = viewModel.topicModeInfo {
                Text("\(topicInfo.index) of \(topicInfo.total)")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }

    private var bottomOverlay: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page.video.topicTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Text(page.video.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if !page.video.description.isEmpty {
                    // Expands in place over the video rather than opening a
                    // full-screen sheet — "more" was covering the whole
                    // screen for what's often two extra lines of text.
                    Text(page.video.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(isCaptionExpanded ? nil : 2)
                    Button(isCaptionExpanded ? "less" : "more") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCaptionExpanded.toggle()
                        }
                    }
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
                onComments: { showComments = true },
                onAITutor: {
                    wasPlayingBeforeAITutor = playbackState == .playing
                    if wasPlayingBeforeAITutor {
                        viewModel.playerPool.togglePlayPause(index: index)
                    }
                    showAITutor = true
                },
                onSave: { viewModel.toggleSave(for: page) },
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
