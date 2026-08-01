import SwiftUI

/// `.navigationDestination(item:)` requires `Identifiable`, which `[Video]`
/// isn't — this is just that wrapper, not a meaningful type on its own.
private struct VideoListDestination: Identifiable {
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
    @State private var reviewFeed: VideoListDestination?

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
                            progressSection
                            likedSection
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
            .task { await viewModel.load() }
            .navigationDestination(item: $likedVideosFeed) { destination in
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
        .sheet(isPresented: $showEditProfile, onDismiss: { Task { await viewModel.load() } }) {
            EditProfileSheet(environment: environment, account: viewModel.account)
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

    @ViewBuilder
    private var likedSection: some View {
        if !viewModel.likedVideos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Liked videos")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 20)

                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(viewModel.likedVideos) { liked in
                        Button {
                            Task { await openLikedFeed(startingAt: liked) }
                        } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.surfaceSubtle)
                                .aspectRatio(9.0 / 16.0, contentMode: .fill)
                                .overlay(Image(systemName: "play.fill").foregroundStyle(theme.textTertiary))
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
        }
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
        async let dueTask = environment.progress.dueForReview(limit: 200)

        let categories = (try? await categoriesTask) ?? []
        let topicProgressList = (try? await topicProgressTask) ?? []
        likedVideos = (try? await likedTask) ?? []
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

    func dueForReviewVideos() async throws -> [Video] {
        let due = try await environment.progress.dueForReview(limit: 200)
        let videos = try await environment.videos.videos(withIds: due.map(\.videoId))
        let orderedIDs = due.map(\.videoId)
        return orderedIDs.compactMap { id in videos.first { $0.id == id } }
    }
}
