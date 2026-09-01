import SwiftUI

@MainActor
final class SocialFeedViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    /// `nil` == "All" — the affinity-first/popularity-fallback pass (§6.2).
    /// Any other value is a single category chip filter.
    @Published var selectedCategoryId: String?
    @Published private(set) var videos: [Video] = []
    @Published private(set) var isLoading = false
    @Published var searchText = ""

    private let environment: AppEnvironment
    private static let pageSize = 30

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Client-side only, over whatever's already loaded into `videos` — not
    /// a real search index (phase-07 §6's own honesty about this, mirroring
    /// Phase 3's topic-search caveat).
    var filteredVideos: [Video] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return videos }
        return videos.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    func loadCategories() async {
        categories = (try? await environment.categories.list()) ?? []
    }

    func loadFeed() async {
        isLoading = true
        defer { isLoading = false }

        if let selectedCategoryId {
            let page = try? await environment.videos.socialFeed(categoryIds: [selectedCategoryId], limit: Self.pageSize, after: nil)
            videos = page?.items ?? []
            return
        }

        // Two-pass: affinity first (the learner's own chosen interests),
        // backfilled with the general popularity ranking once that page
        // runs thin — the concrete shape of "ranked by reference, not fully
        // random" from phase-07 §6.2, not a live learned ranker.
        let interests = environment.currentUser?.interests ?? []
        var combined: [Video] = []
        if !interests.isEmpty {
            let affinityPage = try? await environment.videos.socialFeed(categoryIds: interests, limit: Self.pageSize, after: nil)
            combined = affinityPage?.items ?? []
        }
        if combined.count < Self.pageSize {
            let seenIds = Set(combined.compactMap(\.id))
            let fallbackPage = try? await environment.videos.socialFeed(limit: Self.pageSize, after: nil)
            let fallback = (fallbackPage?.items ?? []).filter { !seenIds.contains($0.id ?? "") }
            combined += fallback
        }
        videos = combined
    }
}

/// phase-07 §6 — replaces Learn as the primary scrolling tab. Category
/// chips and search sit in a custom overlay bar rather than `.searchable`,
/// since `FeedView` hides the system nav bar unconditionally (immersive
/// full-screen playback) and `.searchable` needs one to render into.
struct SocialFeedView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: SocialFeedViewModel
    @State private var showCreateLesson = false
    @State private var showSearchField = false

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: SocialFeedViewModel(environment: environment))
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
            topBar
        }
        .task {
            await viewModel.loadCategories()
            await viewModel.loadFeed()
        }
        .onChange(of: viewModel.selectedCategoryId) { _, _ in
            Task { await viewModel.loadFeed() }
        }
        .sheet(isPresented: $showCreateLesson, onDismiss: { Task { await viewModel.loadFeed() } }) {
            CreateLessonView(environment: environment)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.videos.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).shuiShellBackground()
                .ringSwipeNavigation(isRoot: true)
        } else if viewModel.filteredVideos.isEmpty {
            emptyState
                .ringSwipeNavigation(isRoot: true)
        } else {
            // `.id` forces a fresh `FeedView` — and a fresh player pool —
            // whenever the underlying video list actually changes (a chip
            // tap, a reload), since `.videoList` mode takes its list once at
            // init and never re-observes it.
            FeedView(mode: .videoList(videos: viewModel.filteredVideos), environment: environment, isTabRoot: true)
                .id(feedIdentity)
        }
    }

    private var feedIdentity: String {
        let ids = viewModel.filteredVideos.compactMap(\.id).joined(separator: ",")
        return "\(viewModel.selectedCategoryId ?? "all")-\(ids.count)-\(ids.hashValue)"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)
            Text(viewModel.searchText.isEmpty ? "No lessons here yet" : "No matches")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            if viewModel.searchText.isEmpty {
                Text("Be the first to create one, or check back soon.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Create a lesson") { showCreateLesson = true }
                    .buttonStyle(.shuiPill)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shuiShellBackground()
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { showSearchField.toggle() } } label: {
                    Image(systemName: showSearchField ? "xmark.circle.fill" : "magnifyingglass")
                }
                if showSearchField {
                    TextField("Search lessons", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                Spacer()
                Button { showCreateLesson = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("New lesson")
            }
            .font(.title3)
            .foregroundStyle(theme.textOnAccent)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "All", isSelected: viewModel.selectedCategoryId == nil) {
                        viewModel.selectedCategoryId = nil
                    }
                    ForEach(viewModel.categories) { category in
                        if let categoryId = category.id {
                            categoryChip(title: category.title, isSelected: viewModel.selectedCategoryId == categoryId) {
                                viewModel.selectedCategoryId = categoryId
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.shuiPillOutline)
            .opacity(isSelected ? 1 : 0.6)
    }
}
