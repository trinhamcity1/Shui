import SwiftUI

/// Level 1 of the Explore tab: search, a "Continue learning" row of
/// in-progress topics, and the 11-category grid. Levels 2 and 3
/// (`CategoryPageView`, `TopicPageView`) push from here.
struct ExploreView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var categories: [Category] = []
    @State private var continueTopics: [(topic: Topic, progress: TopicProgress)] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var searchResults: [Topic] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty {
                    searchResultsList
                } else {
                    content
                }
            }
            .navigationTitle(Strings.exploreTab)
            .shuiShellBackground()
            .task { await load() }
        }
        .searchable(text: $searchText, prompt: "Search topics")
        .onChange(of: searchText) { _, newValue in
            Task { await search(newValue) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !continueTopics.isEmpty {
                        continueLearningSection
                    }
                    categoriesSection
                }
                .padding(.vertical, 16)
            }
            // `.task` only runs once per view lifetime — TabView keeps every
            // tab's hierarchy alive, so switching away and back never
            // re-triggers it. Without this, topicCount (and everything else
            // here) can only ever go stale until the app relaunches.
            .refreshable { await load() }
        }
    }

    private var continueLearningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue learning")
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueTopics, id: \.topic.id) { entry in
                        NavigationLink {
                            TopicPageView(topicId: entry.topic.id ?? "", environment: environment)
                        } label: {
                            ContinueLearningCard(topic: entry.topic, progress: entry.progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var categoriesSection: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.title3.bold())
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryPageView(category: category, environment: environment)
                    } label: {
                        CategoryTile(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            VStack(spacing: 8) {
                Text("No topics found")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("Search covers topic titles, not videos.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(searchResults) { topic in
                        NavigationLink {
                            TopicPageView(topicId: topic.id ?? "", environment: environment)
                        } label: {
                            TopicSearchRow(topic: topic)
                        }
                    }
                } footer: {
                    Text("Search covers topic titles, not individual videos.")
                }
            }
            .listStyle(.plain)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let categoriesTask = environment.categories.list()
        async let topicProgressTask = environment.progress.topicProgress()
        let (fetchedCategories, topicProgressList) = await (
            (try? categoriesTask) ?? [],
            (try? topicProgressTask) ?? []
        )
        categories = fetchedCategories.sorted { $0.sortOrder < $1.sortOrder }

        var entries: [(Topic, TopicProgress)] = []
        for progress in topicProgressList where progress.videosCompleted < progress.videosTotal {
            if let topic = try? await environment.topics.topic(id: progress.topicId) {
                entries.append((topic, progress))
            }
        }
        continueTopics = entries.sorted { $0.1.lastActivityAt ?? .distantPast > $1.1.lastActivityAt ?? .distantPast }
    }

    private func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        // Client-side prefix match over what's already cached on this
        // screen (title or tags), supplemented by a title-prefix range
        // query for topics never fetched here at all — per the phase spec,
        // this finds topics, not videos, and doesn't pretend to be real
        // full-text search.
        let normalized = trimmed.lowercased()
        let cachedMatches = continueTopics.map(\.topic).filter { topic in
            topic.title.lowercased().hasPrefix(normalized)
                || topic.tags.contains { $0.lowercased().hasPrefix(normalized) }
        }
        let remoteMatches = (try? await environment.topics.searchByTitlePrefix(trimmed, limit: 20)) ?? []

        var seen = Set<String>()
        var combined: [Topic] = []
        for topic in cachedMatches + remoteMatches {
            guard let id = topic.id, !seen.contains(id) else { continue }
            seen.insert(id)
            combined.append(topic)
        }
        searchResults = combined
    }
}

private struct CategoryTile: View {
    @Environment(\.theme) private var theme
    let category: Category

    private var accent: Color {
        Color(hex: UInt32(category.accentHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xB4530A)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.sfSymbol)
                .font(.title2)
                .foregroundStyle(accent)
            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.leading)
            Text("\(category.topicCount) topic\(category.topicCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
    }
}

private struct ContinueLearningCard: View {
    @Environment(\.theme) private var theme
    let topic: Topic
    let progress: TopicProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TopicCoverThumbnail(urlString: topic.coverImageURL)
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            MasteryBar(percent: progress.masteryPercent)
                .frame(width: 160)
        }
    }
}

struct MasteryBar: View {
    @Environment(\.theme) private var theme
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.surfaceSubtle)
                    Capsule().fill(theme.accent).frame(width: geo.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 6)
            Text("\(percent)% mastery")
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mastery")
        .accessibilityValue("\(percent) percent")
    }
}

private struct TopicSearchRow: View {
    @Environment(\.theme) private var theme
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(topic.subtitle)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
