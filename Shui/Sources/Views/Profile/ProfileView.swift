import SwiftUI

/// `.navigationDestination(item:)` requires `Hashable` (not `Identifiable` —
/// that's `.sheet(item:)`'s requirement, easy to mix up), which `[Video]`
/// isn't on its own — this is just that wrapper. Every stored property here
/// is already `Hashable` (`Video` itself conforms), so the compiler
/// synthesizes `==`/`hash(into:)` for free.
private struct VideoListDestination: Identifiable, Hashable {
    let id = UUID()
    let videos: [Video]
    var startingAtVideoId: String?
}

/// Header, three sections (progress by subject / liked videos / activity),
/// and a settings entry point. Everything here reads from
/// `users/{uid}/topicProgress` and `users/{uid}/likes` — never recomputed
/// from raw events on the client, per the phase spec.
struct ProfileView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: ProfileViewModel
    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var likedVideosFeed: VideoListDestination?
    @State private var savedVideosFeed: VideoListDestination?
    @State private var reviewFeed: VideoListDestination?
    @State private var showSignInSheet = false
    @State private var collectionsTab: CollectionsTab = .saved
    @State private var showCreateLesson = false
    @State private var wallet: Wallet?

    private enum CollectionsTab: String, CaseIterable, Identifiable {
        case saved = "Saved"
        case liked = "Liked"
        var id: String { rawValue }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: ProfileViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            header
                            guestBanner
                            lessonsSection
                            progressSection
                            collectionsSection
                            activitySection
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(Strings.profileTab)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .shuiShellBackground()
            .task {
                await viewModel.load()
                if viewModel.savedVideos.isEmpty && !viewModel.likedVideos.isEmpty {
                    collectionsTab = .liked
                }
                wallet = try? await environment.billing.wallet()
            }
            // Profile's own root — see the matching comment on
            // `ExploreView` for why this is `isRoot: true` while the
            // pushed video feeds below are not.
            .ringSwipeNavigation(isRoot: true)
            .navigationDestination(item: $likedVideosFeed) { destination in
                FeedView(
                    mode: .videoList(videos: destination.videos, startingAtVideoId: destination.startingAtVideoId),
                    environment: environment
                )
            }
            .navigationDestination(item: $savedVideosFeed) { destination in
                FeedView(
                    mode: .videoList(videos: destination.videos, startingAtVideoId: destination.startingAtVideoId),
                    environment: environment
                )
            }
            .navigationDestination(item: $reviewFeed) { destination in
                FeedView(mode: .videoList(videos: destination.videos), environment: environment)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await viewModel.load() } }) {
            SettingsView(environment: environment, isPresented: $showSettings)
        }
        .sheet(isPresented: $showCreateLesson, onDismiss: { Task { wallet = try? await environment.billing.wallet() } }) {
            CreateLessonView(environment: environment)
        }
        .sheet(isPresented: $showEditProfile, onDismiss: { Task { await viewModel.load() } }) {
            EditProfileSheet(environment: environment, account: viewModel.account)
        }
        .sheet(isPresented: $showSignInSheet, onDismiss: { Task { await viewModel.load() } }) {
            SignInSheet()
        }
    }

    /// A guest landing on their own (necessarily sparse) Profile is exactly
    /// the kind of "moment of need" the phase spec wants prompts reserved
    /// for — showing up here rather than nagging on launch — so this isn't
    /// deferred to a later phase the way a real "who am I" identity system
    /// would be.
    @ViewBuilder
    private var guestBanner: some View {
        if environment.isGuest {
            VStack(alignment: .leading, spacing: 10) {
                Text("You're browsing as a guest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Sign in to save your progress and see it across devices.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                Button("Sign in") { showSignInSheet = true }
                    .buttonStyle(.shuiPill)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(theme.surfaceSubtle)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").foregroundStyle(theme.textTertiary))

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.account?.displayName ?? "Learner")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                if let handle = viewModel.account?.handle, !handle.isEmpty {
                    Text("@\(handle)")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                Label("\(viewModel.account?.currentStreak ?? 0) day streak", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(theme.warning)
            }
            Spacer()
            Button("Edit") { showEditProfile = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 20)
    }

    /// Entry points for phase-07's on-demand lessons — "Create" is the
    /// first-screen affordance the phase spec calls for (§9), "My Lessons"
    /// and the balance/plan link sit right alongside it since they're the
    /// natural next things a learner reaches for from here.
    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lessons")
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Button { showCreateLesson = true } label: {
                    HStack {
                        Label("Create a lesson", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink { MyLessonsView(environment: environment) } label: {
                    activityRow("My Lessons", value: "", isLink: true)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink { BillingView(environment: environment) } label: {
                    activityRow("Balance & plan", value: wallet?.creditBalanceDisplay ?? "—", isLink: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if !viewModel.categoryProgress.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progress by subject")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    ForEach(viewModel.categoryProgress) { entry in
                        CategoryProgressRow(
                            entry: entry,
                            isExpanded: expandedCategoryIDs.contains(entry.category.id ?? ""),
                            onToggle: {
                                guard let id = entry.category.id else { return }
                                if expandedCategoryIDs.contains(id) {
                                    expandedCategoryIDs.remove(id)
                                } else {
                                    expandedCategoryIDs.insert(id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// A single segmented "Your videos" section rather than two grids
    /// stacked one after another — mirrors the shelf pattern short-video
    /// apps use for exactly this (a creator's own posts, likes, and saves
    /// as tabs of one shelf, not three growing lists competing for scroll
    /// space). Both grids share `TopicCoverThumbnail` for a real frame from
    /// the video instead of a generic placeholder rectangle.
    @ViewBuilder
    private var collectionsSection: some View {
        if !viewModel.savedVideos.isEmpty || !viewModel.likedVideos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your videos")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 20)

                Picker("Collection", selection: $collectionsTab) {
                    Text("Saved (\(viewModel.savedVideos.count))").tag(CollectionsTab.saved)
                    Text("Liked (\(viewModel.likedVideos.count))").tag(CollectionsTab.liked)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                switch collectionsTab {
                case .saved:
                    if viewModel.savedVideos.isEmpty {
                        collectionEmptyHint("Tap the bookmark on a video to save it here.")
                    } else {
                        savedGrid
                    }
                case .liked:
                    if viewModel.likedVideos.isEmpty {
                        collectionEmptyHint("Tap the heart on a video to like it.")
                    } else {
                        likedGrid
                    }
                }
            }
        }
    }

    private func collectionEmptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    private var savedGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.savedVideos) { saved in
                Button {
                    Task { await openSavedFeed(startingAt: saved) }
                } label: {
                    TopicCoverThumbnail(urlString: saved.thumbnailURL)
                        .aspectRatio(9.0 / 16.0, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove from Saved", role: .destructive) {
                        Task { await viewModel.unsave(saved) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var likedGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.likedVideos) { liked in
                Button {
                    Task { await openLikedFeed(startingAt: liked) }
                } label: {
                    TopicCoverThumbnail(urlString: liked.thumbnailURL)
                        .aspectRatio(9.0 / 16.0, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Unlike", role: .destructive) {
                        Task { await viewModel.unlike(liked) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var activitySection: some View {
        if let account = viewModel.account {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    activityRow("Videos completed", value: "\(account.totalVideosCompleted)")
                    Divider()
                    activityRow("Quizzes passed", value: "\(account.totalQuizzesPassed)")
                    Divider()
                    activityRow("Overall accuracy", value: viewModel.overallAccuracyLabel)
                    Divider()
                    activityRow("Longest streak", value: "\(account.longestStreak) days")
                    if viewModel.dueForReviewCount > 0 {
                        Divider()
                        Button {
                            Task { await openReviewFeed() }
                        } label: {
                            activityRow("Due for review", value: "\(viewModel.dueForReviewCount)", isLink: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func activityRow(_ label: String, value: String, isLink: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(isLink ? theme.accent : theme.textSecondary)
            if isLink {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, 10)
    }

    private func openLikedFeed(startingAt liked: LikedVideo) async {
        let ids = viewModel.likedVideos.map(\.videoId)
        guard let videos = try? await environment.videos.videos(withIds: ids) else { return }
        let ordered = ids.compactMap { id in videos.first { $0.id == id } }
        likedVideosFeed = VideoListDestination(videos: ordered, startingAtVideoId: liked.videoId)
    }

    private func openSavedFeed(startingAt saved: SavedVideo) async {
        let ids = viewModel.savedVideos.map(\.videoId)
        guard let videos = try? await environment.videos.videos(withIds: ids) else { return }
        let ordered = ids.compactMap { id in videos.first { $0.id == id } }
        savedVideosFeed = VideoListDestination(videos: ordered, startingAtVideoId: saved.videoId)
    }

    private func openReviewFeed() async {
        guard let videos = try? await viewModel.dueForReviewVideos() else { return }
        reviewFeed = VideoListDestination(videos: videos)
    }
}

private struct CategoryProgressRow: View {
    @Environment(\.theme) private var theme
    let entry: ProfileViewModel.CategoryProgressEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: entry.category.sfSymbol)
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.category.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(entry.startedTopicCount) of \(entry.topics.count) topics started")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            MasteryBar(percent: entry.aggregateMastery)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.topics) { topic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.topicTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.textPrimary)
                            MasteryBar(percent: topic.masteryPercent)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 28)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    struct CategoryProgressEntry: Identifiable {
        let category: Category
        let topics: [TopicProgress]
        var id: String { category.id ?? category.title }
        var startedTopicCount: Int { topics.count }
        var aggregateMastery: Int {
            guard !topics.isEmpty else { return 0 }
            return topics.map(\.masteryPercent).reduce(0, +) / topics.count
        }
    }

    @Published private(set) var account: UserAccount?
    @Published private(set) var categoryProgress: [CategoryProgressEntry] = []
    @Published private(set) var likedVideos: [LikedVideo] = []
    @Published private(set) var savedVideos: [SavedVideo] = []
    @Published private(set) var dueForReviewCount = 0
    @Published private(set) var isLoading = true

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var overallAccuracyLabel: String {
        let totalCorrect = categoryProgress.flatMap(\.topics).map(\.correctAnswers).reduce(0, +)
        let totalAnswered = categoryProgress.flatMap(\.topics).map(\.totalAnswers).reduce(0, +)
        guard totalAnswered > 0 else { return "—" }
        return "\(Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded()))%"
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await environment.refreshCurrentUser()
        account = environment.currentUser

        async let categoriesTask = environment.categories.list()
        async let topicProgressTask = environment.progress.topicProgress()
        async let likedTask = environment.social.likedVideos()
        async let savedTask = environment.social.savedVideos()
        async let dueTask = environment.progress.dueForReview(limit: 200)

        let categories = (try? await categoriesTask) ?? []
        let topicProgressList = (try? await topicProgressTask) ?? []
        likedVideos = (try? await likedTask) ?? []
        savedVideos = (try? await savedTask) ?? []
        dueForReviewCount = (try? await dueTask)?.count ?? 0

        let grouped = Dictionary(grouping: topicProgressList, by: \.categoryId)
        categoryProgress = categories
            .compactMap { category -> CategoryProgressEntry? in
                guard let id = category.id, let topics = grouped[id], !topics.isEmpty else { return nil }
                return CategoryProgressEntry(category: category, topics: topics)
            }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    func unlike(_ liked: LikedVideo) async {
        likedVideos.removeAll { $0.id == liked.id }
        _ = try? await environment.social.toggleLike(videoId: liked.videoId)
    }

    func unsave(_ saved: SavedVideo) async {
        savedVideos.removeAll { $0.id == saved.id }
        _ = try? await environment.social.toggleSave(videoId: saved.videoId)
    }

    func dueForReviewVideos() async throws -> [Video] {
        let due = try await environment.progress.dueForReview(limit: 200)
        let videos = try await environment.videos.videos(withIds: due.map(\.videoId))
        let orderedIDs = due.map(\.videoId)
        return orderedIDs.compactMap { id in videos.first { $0.id == id } }
    }
}
