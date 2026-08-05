import SwiftUI

/// Level 1 of the Explore tab: search, a "Continue learning" row of
/// in-progress topics, and the 11-category grid. Levels 2 and 3
/// (`CategoryPageView`, `TopicPageView`) push from here.
struct ExploreView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var categories: [Category] = []
    /// Live per-category counts, keyed by category id — see
    /// `TopicRepository.publicTopicCount(inCategory:)` for why this reads a
    /// fresh aggregate query on every load rather than trusting
    /// `Category.topicCount`, a denormalized counter that's now caused two
    /// separate rounds of "why does this show 0" reports.
    @State private var liveTopicCounts: [String: Int] = [:]
    @State private var continueTopics: [(topic: Topic, progress: TopicProgress)] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var searchResults: [Topic] = []
    @State private var isSearching = false
    /// Debounces search-as-you-type: without it, every keystroke fired its
    /// own Firestore query, wasting reads and — since network responses can
    /// arrive out of order — occasionally letting a stale result for an
    /// earlier, broader keystroke overwrite a newer, more specific one.
    @State private var searchTask: Task<Void, Never>?

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
            // This is Explore's own root — nothing to pop, so a backward
            // swipe here always retreats to Learn instead. Anything pushed
            // from here (a category, a topic, a video) gets its own
            // `isRoot: false` attachment that pops first.
            .ringSwipeNavigation(isRoot: true)
        }
        .searchable(text: $searchText, prompt: "Search topics")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await search(newValue)
            }
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
                        CategoryTile(category: category, topicCount: liveTopicCounts[category.id ?? ""] ?? category.topicCount)
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

        // One aggregate query per category, all concurrent — 11 categories
        // means 11 near-free reads in parallel, not 11 round trips in
        // series.
        liveTopicCounts = await withTaskGroup(of: (String, Int).self) { group in
            for category in fetchedCategories {
                guard let categoryId = category.id else { continue }
                group.addTask {
                    let count = (try? await environment.topics.publicTopicCount(inCategory: categoryId)) ?? category.topicCount
                    return (categoryId, count)
                }
            }
            var results: [String: Int] = [:]
            for await (categoryId, count) in group {
                results[categoryId] = count
            }
            return results
        }

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

        // Three sources merged: a cheap local prefix check over what's
        // already cached on this screen, a title-prefix range query (still
        // needed — `arrayContainsAny` only matches *complete* words, so it
        // can't catch "still typing the first word"), and the keyword-index
        // query, which is what actually answers "healing", "fullest",
        // "life live" — any complete word, anywhere in the topic's title,
        // subtitle, description, or tags, not just how it starts.
        let normalized = trimmed.lowercased()
        let cachedMatches = continueTopics.map(\.topic).filter { topic in
            topic.title.lowercased().hasPrefix(normalized)
                || topic.tags.contains { $0.lowercased().hasPrefix(normalized) }
        }
        async let prefixTask = environment.topics.searchByTitlePrefix(trimmed, limit: 20)
        async let keywordTask = environment.topics.searchByKeywords(trimmed, limit: 20)
        let (prefixMatches, keywordMatches) = await ((try? prefixTask) ?? [], (try? keywordTask) ?? [])

        var seen = Set<String>()
        var combined: [Topic] = []
        // Title-prefix matches lead — "How to" typed against a topic titled
        // "How to..." is the clearest possible match a query can make, and
        // shouldn't be out-ranked by a keyword hit buried in a description.
        for topic in cachedMatches + prefixMatches + keywordMatches {
            guard let id = topic.id, !seen.contains(id) else { continue }
            seen.insert(id)
            combined.append(topic)
        }

        // Everything after the prefix-matched lead group is ranked by how
        // many of the typed words it actually contains — not real
        // relevance scoring (no field weighting, no typo tolerance), just
        // "more of what you typed" over an arbitrary/database order. Real
        // ranking (and where a paid "boosted" topic would plug in) is
        // future, separate work — see PROGRESS.md.
        let queryTokens = Set(SearchKeywords.query(trimmed))
        let prefixMatchedIDs = Set(prefixMatches.compactMap(\.id))
        combined.sort { lhs, rhs in
            let lhsIsPrefixMatch = prefixMatchedIDs.contains(lhs.id ?? "")
            let rhsIsPrefixMatch = prefixMatchedIDs.contains(rhs.id ?? "")
            if lhsIsPrefixMatch != rhsIsPrefixMatch { return lhsIsPrefixMatch }
            return matchScore(lhs, against: queryTokens) > matchScore(rhs, against: queryTokens)
        }

        searchResults = combined
    }

    private func matchScore(_ topic: Topic, against queryTokens: Set<String>) -> Int {
        let keywords = SearchKeywords.index(
            title: topic.title, subtitle: topic.subtitle, description: topic.description, tags: topic.tags
        )
        return keywords.filter(queryTokens.contains).count
    }
}

private struct CategoryTile: View {
    @Environment(\.theme) private var theme
    let category: Category
    /// Passed in rather than read from `category.topicCount` directly — see
    /// `ExploreView.load()`, which resolves this from a live query.
    let topicCount: Int

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
            Text("\(topicCount) topic\(topicCount == 1 ? "" : "s")")
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
