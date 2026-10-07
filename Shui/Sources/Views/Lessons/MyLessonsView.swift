import SwiftUI

@MainActor
final class MyLessonsViewModel: ObservableObject {
    @Published private(set) var lessons: [Video] = []
    @Published private(set) var isLoading = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        var fetched = (try? await environment.videos.myLessons()) ?? []
        await refreshStuckGeneratingLessons(fetched)
        // Re-fetch rather than patch in place: checkOnDemandLessonStatus just
        // wrote playbackURL/status/etc. server-side, and that's the one
        // source of truth for what actually changed, not anything derivable
        // from the poll response alone.
        if fetched.contains(where: { $0.status == .generating }) {
            fetched = (try? await environment.videos.myLessons()) ?? fetched
        }
        lessons = fetched
    }

    /// A lesson only ever gets polled while `CreateLessonView`'s own sheet is
    /// open (`CreateLessonViewModel.startPolling`) — if that sheet closes
    /// before GolpoAI finishes (an error, a dismiss, the app backgrounded),
    /// nothing else in the app was ever going to check on it again, and it
    /// stayed "generating" forever even after the render actually completed.
    /// Every load of this screen gets each still-generating lesson one more
    /// chance to finalize instead.
    private func refreshStuckGeneratingLessons(_ videos: [Video]) async {
        let generatingIds = videos.compactMap { $0.status == .generating ? $0.id : nil }
        guard !generatingIds.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for videoId in generatingIds {
                group.addTask { _ = try? await self.environment.onDemandLessons.checkStatus(videoId: videoId) }
            }
        }
    }
}

/// phase-07 §9 — `videos` where `topicId == "personal-{uid}"`, newest first,
/// each row showing its status inline. Reuses `CreatorVideoRow`/
/// `StatusBadge` from the Creator topic editor (§9's "no second
/// video-list view") rather than a bespoke row.
///
/// Row interaction is a swipe-to-reveal gear (`SwipeToRevealRow` below)
/// rather than `.swipeActions` — opening Lesson Settings (title, thumbnail,
/// quiz, share/unshare, download, delete) needed more than one action, so a
/// single settings page replaced the old one-off "Share to Social" swipe
/// action.
struct MyLessonsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: MyLessonsViewModel
    @State private var showCreate = false
    @State private var openedVideo: Video?
    @State private var retryTarget: RetryTarget?
    @State private var settingsTarget: Video?
    /// Only one row revealed at a time — swiping a second row, or swiping
    /// this one back, closes whichever was open. `nil` means none revealed.
    @State private var revealedVideoId: String?

    private struct RetryTarget: Identifiable {
        let id = UUID()
        let topic: String
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: MyLessonsViewModel(environment: environment))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.lessons.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.lessons.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(Array(viewModel.lessons.enumerated()), id: \.element.id) { index, video in
                        VStack(alignment: .leading, spacing: 4) {
                            if index == 0 {
                                Text("Swipe left for settings")
                                    .font(.caption)
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(.horizontal, 4)
                            }
                            row(for: video)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle("My Lessons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New lesson")
            }
        }
        .task { await viewModel.load() }
        .shuiShellBackground()
        .sheet(isPresented: $showCreate, onDismiss: { Task { await viewModel.load() } }) {
            CreateLessonView(environment: environment)
        }
        .sheet(item: $retryTarget, onDismiss: { Task { await viewModel.load() } }) { target in
            CreateLessonView(environment: environment, initialTopic: target.topic)
        }
        .sheet(item: $settingsTarget, onDismiss: { Task { await viewModel.load() } }) { video in
            NavigationStack {
                VideoSettingsView(video: video, environment: environment, onDeleted: { Task { await viewModel.load() } })
            }
        }
        .fullScreenCover(item: $openedVideo) { video in
            FeedView(mode: .videoList(videos: [video]), environment: environment)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)
            Text("No lessons yet")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text("Generate your first lesson on any topic you want to learn.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Create a lesson") { showCreate = true }
                .buttonStyle(.shuiPill)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for video: Video) -> some View {
        SwipeToRevealRow(
            isRevealed: revealedVideoId == video.id,
            onReveal: { revealedVideoId = video.id },
            onClose: { if revealedVideoId == video.id { revealedVideoId = nil } },
            onTapContent: { handleTap(video) },
            onGearTap: {
                revealedVideoId = nil
                settingsTarget = video
            }
        ) {
            HStack {
                CreatorVideoRow(video: video)
                Spacer()
                if let cents = video.costChargedCents, cents > 0 {
                    Text((Double(cents) / 100).formatted(.currency(code: "USD")))
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func handleTap(_ video: Video) {
        switch video.status {
        case .ready:
            openedVideo = video
        case .failed:
            retryTarget = RetryTarget(topic: video.rawTopic ?? video.title)
        case .pending, .uploading, .generating:
            break
        }
    }
}

/// A row with a gear button revealed by swiping left, closed by swiping
/// right or tapping the content — a "trap door," not a persistent action
/// bar. Built as a raw drag gesture rather than `.swipeActions` because
/// Lesson Settings needs one single destination (a gear tap), not a row of
/// independent action buttons.
private struct SwipeToRevealRow<Content: View>: View {
    let isRevealed: Bool
    let onReveal: () -> Void
    let onClose: () -> Void
    let onTapContent: () -> Void
    let onGearTap: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @GestureState private var dragTranslation: CGFloat = 0
    private let revealWidth: CGFloat = 64

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onGearTap) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: revealWidth, height: 64)
                    .background(theme.surfaceSubtle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lesson settings")

            Button {
                if isRevealed {
                    onClose()
                } else {
                    onTapContent()
                }
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(theme.surface)
            .offset(x: min(0, (isRevealed ? -revealWidth : 0) + dragTranslation))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragTranslation) { value, state, _ in
                        let proposed = value.translation.width
                        state = isRevealed
                            ? min(max(proposed, 0), revealWidth)
                            : max(min(proposed, 0), -revealWidth)
                    }
                    .onEnded { value in
                        let translation = value.translation.width
                        if isRevealed {
                            if translation > revealWidth / 2 { onClose() }
                        } else {
                            if translation < -revealWidth / 2 { onReveal() }
                        }
                    }
            )
            .animation(.snappy(duration: 0.25), value: isRevealed)
        }
    }
}
