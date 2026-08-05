import Foundation

/// A topic plus the derived "what's stopping this from being publishable"
/// state the dashboard leads with. Computed here rather than in the view so
/// the rules live in one testable place, and so the dashboard and the topic
/// editor's inline publish checklist can't drift apart.
struct CreatorTopicSummary: Identifiable, Hashable {
    let topic: Topic
    let videos: [Video]

    /// Falls back to the title rather than a fresh `UUID()` — an id that
    /// changes on every access makes SwiftUI treat the row as a different
    /// view each render, which breaks `ForEach` identity and selection. A
    /// persisted topic always has an id, so the fallback is only ever hit
    /// for an unsaved draft.
    var id: String { topic.id ?? "unsaved-\(topic.title)" }

    var readyVideos: [Video] { videos.filter { $0.status == .ready && !$0.isDeleted } }
    var videosNeedingQuiz: [Video] { readyVideos.filter { !$0.hasQuiz } }
    var failedVideos: [Video] { videos.filter { $0.status == .failed } }
    var processingVideos: [Video] { videos.filter { $0.status == .pending || $0.status == .uploading } }

    /// Mirrors `setTopicVisibility`'s server-side gate exactly — at least one
    /// ready, non-deleted video. Shown inline *before* the creator taps
    /// Publish so the Function's rejection is never the first they hear of
    /// it (prompts/phase-05-creator-mode.md §3).
    var canPublish: Bool { !readyVideos.isEmpty }

    /// Ordered by how much they block publishing — the blocking item first,
    /// then quality gaps. Empty means the topic is in good shape.
    var blockers: [String] {
        var items: [String] = []
        if readyVideos.isEmpty {
            items.append(videos.isEmpty ? "No videos yet" : "No videos finished uploading yet")
        }
        if !videosNeedingQuiz.isEmpty {
            let count = videosNeedingQuiz.count
            items.append(count == 1 ? "1 video has no quiz" : "\(count) videos have no quiz")
        }
        if !failedVideos.isEmpty {
            let count = failedVideos.count
            items.append(count == 1 ? "1 upload failed" : "\(count) uploads failed")
        }
        if !processingVideos.isEmpty {
            let count = processingVideos.count
            items.append(count == 1 ? "1 video still uploading" : "\(count) videos still uploading")
        }
        if topic.coverImageURL == nil {
            items.append("No cover image")
        }
        return items
    }

    var totalViews: Int { videos.reduce(0) { $0 + $1.viewCount } }
}

@MainActor
final class CreatorHomeViewModel: ObservableObject {
    @Published private(set) var drafts: [CreatorTopicSummary] = []
    @Published private(set) var published: [CreatorTopicSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isEmpty: Bool { drafts.isEmpty && published.isEmpty && !isLoading }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let topics = try await environment.topics.myTopics()
            // One videos query per topic, run concurrently rather than in
            // series — a creator with a dozen topics would otherwise wait on
            // a dozen sequential round trips before the dashboard paints.
            let summaries = try await withThrowingTaskGroup(of: CreatorTopicSummary.self) { group in
                for topic in topics {
                    group.addTask { [environment] in
                        guard let topicId = topic.id else { return CreatorTopicSummary(topic: topic, videos: []) }
                        let videos = (try? await environment.videos.allVideos(inTopic: topicId)) ?? []
                        return CreatorTopicSummary(topic: topic, videos: videos)
                    }
                }
                var collected: [CreatorTopicSummary] = []
                for try await summary in group { collected.append(summary) }
                return collected
            }

            // The task group returns in completion order, so re-impose the
            // query's ordering (most recently updated first) rather than
            // letting the list jump around between refreshes.
            let order = Dictionary(uniqueKeysWithValues: topics.enumerated().map { ($0.element.id ?? "", $0.offset) })
            let sorted = summaries.sorted { (order[$0.topic.id ?? ""] ?? 0) < (order[$1.topic.id ?? ""] ?? 0) }

            drafts = sorted.filter { $0.topic.visibility == .private }
            published = sorted.filter { $0.topic.visibility == .public }
        } catch {
            errorMessage = "Couldn't load your topics. Pull to refresh."
        }
    }
}
