import Foundation

/// Drives one feed screen — either the mixed Learn tab or a single topic
/// pushed from a topic page (Phase 3). Owns pagination, the player pool,
/// view tracking, and quiz submission (including the offline retry queue).
@MainActor
final class FeedViewModel: ObservableObject {
    enum Mode {
        case mixed
        case topic(topicId: String, startingAtVideoId: String?)
        /// An explicit, already-known list of videos, in order — the
        /// Profile tab's liked-videos grid and "due for review" activity
        /// stat both open a feed this way, bypassing pagination/composition
        /// entirely since the caller already knows exactly which videos and
        /// in what order.
        case videoList(videos: [Video], startingAtVideoId: String? = nil)
    }

    @Published private(set) var pages: [FeedPageViewModel] = []
    @Published var currentIndex = 0
    @Published private(set) var isInitialLoading = true
    @Published private(set) var isLoadingMore = false
    @Published var loadError: String?

    let playerPool = FeedPlayerPool()

    private let mode: Mode
    private let environment: AppEnvironment
    private let persistence: PersistenceController
    private let pageBatchSize = 10

    /// `(position, total)`, 1-indexed, for any fixed-list mode (topic or an
    /// explicit video list) — drives the "3 of 12" pill; `nil` in the mixed
    /// feed, where there's no fixed total.
    var topicModeInfo: (index: Int, total: Int)? {
        switch mode {
        case .topic, .videoList:
            return (currentIndex + 1, pages.count)
        case .mixed:
            return nil
        }
    }

    // Mixed-mode pagination state.
    private var dueForReviewPool: [Video] = []
    private var continueTopicPool: [Video] = []
    private var newInInterestsCursor: PageCursor?
    private var everythingElseCursor: PageCursor?
    private var interests: [String] = []
    private var hasMoreNewInInterests = true
    private var hasMoreEverythingElse = true
    private var hasLoadedInitialBuckets = false

    init(mode: Mode, environment: AppEnvironment, persistence: PersistenceController = .shared) {
        self.mode = mode
        self.environment = environment
        self.persistence = persistence
        playerPool.onEnded = { [weak self] index in
            self?.handlePlayerEnded(at: index)
        }
    }

    // MARK: - Loading

    func loadInitial() async {
        isInitialLoading = true
        loadError = nil
        defer { isInitialLoading = false }

        switch mode {
        case let .topic(topicId, startingAtVideoId):
            await loadTopic(topicId: topicId, startingAtVideoId: startingAtVideoId)
        case .mixed:
            await loadMoreMixed()
        case let .videoList(videos, startingAtVideoId):
            pages = videos.map { FeedPageViewModel(video: $0, source: .everythingElse) }
            if let startingAtVideoId, let idx = videos.firstIndex(where: { $0.id == startingAtVideoId }) {
                currentIndex = idx
            }
        }

        if !pages.isEmpty {
            await prefetchAround(index: currentIndex)
        }
        flushPendingQuizAttempts()
    }

    func loadMoreIfNeeded(currentlyShowing index: Int) {
        guard case .mixed = mode, !isLoadingMore, pages.count - index <= 3 else { return }
        Task { await loadMoreMixed() }
    }

    /// Rebuilds the feed from scratch — pull-to-refresh, and the only way to
    /// pick up content published after the feed already loaded once.
    /// `loadInitial()` alone only ever appends further pages, so simply
    /// calling it again wouldn't show anything newly published; TabView also
    /// keeps this view's `@StateObject` alive across tab switches, so there's
    /// no view-lifecycle event that would trigger a fresh load on its own.
    func refresh() async {
        playerPool.reset()
        pages = []
        currentIndex = 0
        dueForReviewPool = []
        continueTopicPool = []
        newInInterestsCursor = nil
        everythingElseCursor = nil
        hasMoreNewInInterests = true
        hasMoreEverythingElse = true
        hasLoadedInitialBuckets = false
        await loadInitial()
    }

    private func loadTopic(topicId: String, startingAtVideoId: String?) async {
        do {
            let videos = try await environment.videos.videos(inTopic: topicId)
            pages = videos.map { FeedPageViewModel(video: $0, source: .continueTopic) }
            if let startingAtVideoId, let idx = videos.firstIndex(where: { $0.id == startingAtVideoId }) {
                currentIndex = idx
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMoreMixed() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            if !hasLoadedInitialBuckets {
                try await loadInitialBuckets()
                hasLoadedInitialBuckets = true
            }

            let takenReview = Array(dueForReviewPool.prefix(pageBatchSize))
            dueForReviewPool.removeFirst(takenReview.count)

            let takenContinue = Array(continueTopicPool.prefix(pageBatchSize))
            continueTopicPool.removeFirst(takenContinue.count)

            var takenNew: [Video] = []
            if hasMoreNewInInterests, !interests.isEmpty {
                let page = try await environment.videos.feed(
                    categoryIds: interests, limit: pageBatchSize, after: newInInterestsCursor
                )
                takenNew = page.items
                newInInterestsCursor = page.cursor
                hasMoreNewInInterests = page.items.count == pageBatchSize
            }

            var takenRest: [Video] = []
            if hasMoreEverythingElse {
                let page = try await environment.videos.feed(
                    categoryId: nil, limit: pageBatchSize, after: everythingElseCursor
                )
                takenRest = page.items
                everythingElseCursor = page.cursor
                hasMoreEverythingElse = page.items.count == pageBatchSize
            }

            let alreadyPlaced = pages.map { FeedItem(video: $0.video, source: $0.source) }
            let composed = FeedComposer.compose(
                dueForReview: takenReview,
                continueTopic: takenContinue,
                newInInterests: takenNew,
                everythingElse: takenRest,
                alreadyPlaced: alreadyPlaced
            )

            let newPages = composed.map { FeedPageViewModel(video: $0.video, source: $0.source) }
            pages.append(contentsOf: newPages)

            for page in newPages {
                await prefetchQuiz(for: page)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadInitialBuckets() async throws {
        async let dueTask = environment.progress.dueForReview(limit: 30)
        async let topicProgressTask = environment.progress.topicProgress()

        let (dueList, topicProgressList) = try await (dueTask, topicProgressTask)
        interests = environment.currentUser?.interests ?? []

        let dueVideoIds = dueList.map(\.videoId)
        var dueVideos = try await environment.videos.videos(withIds: dueVideoIds)
        dueVideos.sort { a, b in
            (dueVideoIds.firstIndex(of: a.id ?? "") ?? Int.max) < (dueVideoIds.firstIndex(of: b.id ?? "") ?? Int.max)
        }
        dueForReviewPool = dueVideos

        // N+1 on purpose: a topic's video count is small (a few dozen at
        // most for seeded content), and this is the only way to know which
        // of its videos are already watched without a denormalized field.
        if let activeTopic = topicProgressList.first {
            let topicVideos = try await environment.videos.videos(inTopic: activeTopic.topicId)
            var unwatched: [Video] = []
            for video in topicVideos {
                guard let videoId = video.id else { continue }
                let progress = try? await environment.progress.videoProgress(videoId: videoId)
                if progress?.completed != true {
                    unwatched.append(video)
                }
            }
            continueTopicPool = unwatched
        }
    }

    // MARK: - Prefetch / activation

    func onPageAppear(index: Int) {
        currentIndex = index
        playerPool.activate(index: index)
        Task { await prefetchAround(index: index) }
        loadMoreIfNeeded(currentlyShowing: index)
    }

    func onPageDisappear(index: Int) {
        guard pages.indices.contains(index) else { return }
        recordViewIfNeeded(for: pages[index], at: index)
    }

    private func prefetchAround(index: Int) async {
        let window = windowRange(around: index)
        for i in window {
            guard pages.indices.contains(i), let url = URL(string: pages[i].video.playbackURL) else { continue }
            playerPool.prepare(index: i, url: url, window: window)
            if pages[i].video.hasQuiz {
                await prefetchQuiz(for: pages[i])
            }
        }
        playerPool.recycle(outside: window)
    }

    private func windowRange(around index: Int) -> ClosedRange<Int> {
        let lower = max(0, index - 1)
        let upper = min(max(pages.count - 1, 0), index + 2)
        return lower...max(lower, upper)
    }

    private func prefetchQuiz(for page: FeedPageViewModel) async {
        guard page.video.hasQuiz, let videoId = page.video.id else { return }
        let quiz = try? await environment.quizzes.quiz(forVideo: videoId)
        page.quizDidLoad(quiz)
    }

    // MARK: - Playback end -> quiz

    private func handlePlayerEnded(at index: Int) {
        guard pages.indices.contains(index) else { return }
        let page = pages[index]
        page.videoDidEnd()
        recordViewIfNeeded(for: page, at: index)
    }

    func replay(_ page: FeedPageViewModel) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        page.replay()
        playerPool.restart(index: index)
    }

    // MARK: - View tracking

    private func recordViewIfNeeded(for page: FeedPageViewModel, at index: Int) {
        guard !page.hasRecordedView, let videoId = page.video.id else { return }
        page.hasRecordedView = true

        let fraction = playerPool.progress[index] ?? 0
        let watchedSeconds = fraction * page.video.durationSeconds
        let completed = page.endState != .notEnded

        Task {
            try? await environment.videos.recordView(videoId: videoId, watchedSeconds: watchedSeconds, completed: completed)
        }
        if completed || fraction >= 0.9 {
            Task { await markCompleted(for: page, videoId: videoId, watchedSeconds: watchedSeconds) }
        }
    }

    private func markCompleted(for page: FeedPageViewModel, videoId: String, watchedSeconds: Double) async {
        guard !page.hasMarkedCompleted else { return }
        page.hasMarkedCompleted = true
        try? await environment.progress.markCompleted(videoId: videoId, watchedSeconds: watchedSeconds)
    }

    // MARK: - Like

    func toggleLike(for page: FeedPageViewModel) {
        guard let videoId = page.video.id else { return }
        let wasLiked = page.isLiked
        page.isLiked.toggle()
        page.likeCount += page.isLiked ? 1 : -1
        Task {
            do {
                let liked = try await environment.social.toggleLike(videoId: videoId)
                page.isLiked = liked
            } catch {
                page.isLiked = wasLiked
                page.likeCount += wasLiked ? 1 : -1
            }
        }
    }

    // MARK: - Quiz submission

    /// Called on every "Next"/"Submit" tap in the quiz card. Only actually
    /// submits once the last question has been answered — earlier taps just
    /// advance `page`'s local state.
    func advanceQuiz(for page: FeedPageViewModel) {
        guard let answers = page.advanceAnswering() else { return }
        Task { await performSubmission(for: page, answers: answers) }
    }

    func retrySubmission(for page: FeedPageViewModel) {
        let answers = page.collectAnswersForRetry()
        page.beginSubmitting()
        Task { await performSubmission(for: page, answers: answers) }
    }

    private func performSubmission(for page: FeedPageViewModel, answers: [QuizAttemptAnswer]) async {
        guard let videoId = page.video.id else { return }
        let topicId = page.video.topicId
        let before = await currentMasteryPercent(forTopic: topicId)
        do {
            let result = try await environment.quizzes.submit(videoId: videoId, answers: answers)
            let after = await currentMasteryPercent(forTopic: topicId)
            let delta: Int? = {
                guard let before, let after else { return nil }
                return after - before
            }()
            page.receiveResult(result, masteryDelta: delta)
            for pending in persistence.pendingQuizAttempts() where pending.videoID == videoId {
                persistence.delete(pending)
            }
        } catch {
            persistence.insert(PendingQuizAttempt(videoID: videoId, answers: answers))
            page.failSubmission()
        }
    }

    private func currentMasteryPercent(forTopic topicId: String) async -> Int? {
        let list = (try? await environment.progress.topicProgress()) ?? []
        return list.first(where: { $0.topicId == topicId })?.masteryPercent
    }

    /// Retries every queued attempt, oldest first. Called at feed launch and
    /// again whenever connectivity comes back — an attempt that still fails
    /// stays queued and stops the flush rather than reordering the queue.
    func flushPendingQuizAttempts() {
        let pending = persistence.pendingQuizAttempts()
        guard !pending.isEmpty else { return }
        Task {
            for attempt in pending {
                do {
                    let result = try await environment.quizzes.submit(videoId: attempt.videoID, answers: attempt.answers)
                    persistence.delete(attempt)
                    if let page = pages.first(where: { $0.video.id == attempt.videoID }),
                       case .submissionFailed = page.endState {
                        page.receiveResult(result, masteryDelta: nil)
                    }
                } catch {
                    break
                }
            }
        }
    }
}
