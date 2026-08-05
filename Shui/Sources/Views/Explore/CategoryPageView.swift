import SwiftUI

/// Level 2 of the Explore tab: every public topic in one category, sorted
/// newest or most-learners, paginated.
struct CategoryPageView: View {
    let category: Category
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CategoryPageViewModel

    init(category: Category, environment: AppEnvironment) {
        self.category = category
        self.environment = environment
        _viewModel = StateObject(wrappedValue: CategoryPageViewModel(category: category, environment: environment))
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(viewModel.topics) { topic in
                    NavigationLink {
                        TopicPageView(topicId: topic.id ?? "", environment: environment)
                    } label: {
                        TopicRow(topic: topic, mastery: viewModel.mastery[topic.id ?? ""])
                    }
                    .onAppear { viewModel.loadMoreIfNeeded(currentlyShowing: topic) }
                }
                if viewModel.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
        // See the matching comment on `TopicPageView` — same treatment,
        // one level up the stack.
        .ringSwipeNavigation(onSwipeBack: dismiss.callAsFunction)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !category.description.isEmpty {
                Text(category.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Picker("Sort", selection: $viewModel.sort) {
                Text("Newest").tag(TopicSort.newest)
                Text("Most learners").tag(TopicSort.mostLearners)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.sort) { _, _ in
                Task { await viewModel.loadInitial() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

@MainActor
final class CategoryPageViewModel: ObservableObject {
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var mastery: [String: Int] = [:]
    @Published private(set) var isLoadingMore = false
    @Published var sort: TopicSort = .newest

    private let category: Category
    private let environment: AppEnvironment
    private var cursor: PageCursor?
    private var hasMore = true
    private let pageSize = 20

    init(category: Category, environment: AppEnvironment) {
        self.category = category
        self.environment = environment
    }

    func loadInitial() async {
        topics = []
        cursor = nil
        hasMore = true
        await loadMore()
        await loadMasteryForVisibleTopics()
    }

    func loadMoreIfNeeded(currentlyShowing topic: Topic) {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }), topics.count - index <= 5 else { return }
        Task {
            await loadMore()
            await loadMasteryForVisibleTopics()
        }
    }

    private func loadMore() async {
        guard let categoryId = category.id, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await environment.topics.topics(
            inCategory: categoryId, sortedBy: sort, limit: pageSize, after: cursor
        ) else { return }
        topics.append(contentsOf: page.items)
        cursor = page.cursor
        hasMore = page.items.count == pageSize
    }

    /// N+1 on purpose, same tradeoff `FeedViewModel` already makes for
    /// per-topic progress — a category page shows a modest number of topics
    /// at a time, and there's no denormalized "my mastery" field on the
    /// public topic document itself (rules keep progress owner-only).
    private func loadMasteryForVisibleTopics() async {
        let allProgress = (try? await environment.progress.topicProgress()) ?? []
        var updated = mastery
        for topic in topics {
            guard let id = topic.id, updated[id] == nil else { continue }
            if let match = allProgress.first(where: { $0.topicId == id }) {
                updated[id] = match.masteryPercent
            }
        }
        mastery = updated
    }
}

private struct TopicRow: View {
    @Environment(\.theme) private var theme
    let topic: Topic
    let mastery: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TopicCoverThumbnail(urlString: topic.coverImageURL)
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text(topic.subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(topic.videoCount)", systemImage: "play.rectangle")
                    Label(durationLabel, systemImage: "clock")
                    Label("\(topic.learnerCount)", systemImage: "person.2")
                }
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)

                if let mastery {
                    MasteryBar(percent: mastery)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var durationLabel: String {
        let minutes = Int(topic.totalDurationSec / 60)
        return "\(minutes)m"
    }
}
