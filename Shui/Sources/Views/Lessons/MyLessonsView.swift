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
struct MyLessonsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: MyLessonsViewModel
    @State private var showCreate = false
    @State private var openedVideo: Video?
    @State private var retryTarget: RetryTarget?
    @State private var shareErrorMessage: String?

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
                    ForEach(viewModel.lessons) { video in
                        row(for: video)
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
        .fullScreenCover(item: $openedVideo) { video in
            FeedView(mode: .videoList(videos: [video]), environment: environment)
        }
        .alert("Couldn't share", isPresented: Binding(get: { shareErrorMessage != nil }, set: { if !$0 { shareErrorMessage = nil } })) {
            Button(Strings.done, role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
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
        Button {
            handleTap(video)
        } label: {
            HStack {
                CreatorVideoRow(video: video)
                Spacer()
                if let cents = video.costChargedCents, cents > 0 {
                    Text((Double(cents) / 100).formatted(.currency(code: "USD")))
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if canShare(video) {
                Button("Share to Social") { Task { await shareTapped(video) } }
                    .tint(theme.accent)
            }
        }
    }

    private func canShare(_ video: Video) -> Bool {
        video.status == .ready && video.sharedToSocial != true && video.originatedFromApi != true
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

    private func shareTapped(_ video: Video) async {
        guard let videoId = video.id else { return }
        AppAnalytics.logFeatureTap(.shareToSocial)
        do {
            _ = try await environment.onDemandLessons.shareToSocial(videoId: videoId)
            await viewModel.load()
        } catch {
            shareErrorMessage = error.localizedDescription
        }
    }
}
