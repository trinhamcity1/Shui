import SwiftUI

enum VideoLearnerState {
    case unwatched, watched, quizPassed, needsReview

    var systemImage: String {
        switch self {
        case .unwatched: return "circle"
        case .watched: return "checkmark.circle"
        case .quizPassed: return "checkmark.seal.fill"
        case .needsReview: return "arrow.counterclockwise.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .unwatched: return "Not started"
        case .watched: return "Watched"
        case .quizPassed: return "Quiz passed"
        case .needsReview: return "Needs review"
        }
    }
}

/// Level 3 of the Explore tab — the most important screen in it, per the
/// phase spec: cover, progress, description, and the ordered video list
/// that's the actual entry point into Phase 2's feed in topic mode.
struct TopicPageView: View {
    let topicId: String
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TopicPageViewModel
    @State private var isDescriptionExpanded = false

    init(topicId: String, environment: AppEnvironment) {
        self.topicId = topicId
        self.environment = environment
        _viewModel = StateObject(wrappedValue: TopicPageViewModel(topicId: topicId, environment: environment))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.loadError {
                FeedErrorStateView(message: errorMessage, onRetry: { Task { await viewModel.load() } })
            } else if let topic = viewModel.topic {
                content(topic: topic)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .shuiShellBackground()
        .task { await viewModel.load() }
        // Pushed on top of Explore's own stack — a backward swipe pops
        // back to whatever's underneath (Explore's root, or a category),
        // not the ring. The system nav bar's own back button/edge-swipe
        // stays too; this just adds the same full-screen gesture the video
        // feed uses, so the two feel consistent.
        .ringSwipeNavigation(isRoot: false, onSwipeBack: dismiss.callAsFunction)
    }

    @ViewBuilder
    private func content(topic: Topic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cover(topic: topic)
                header(topic: topic)
                startButton(topic: topic)
                if let progress = viewModel.topicProgress {
                    progressBlock(progress)
                }
                descriptionSection(topic: topic)
                videoList
            }
            .padding(.bottom, 32)
        }
    }

    /// A fixed warm-cream, not `theme.textPrimary` — the scrim underneath is
    /// the same near-black in both app themes, so the title needs to stay
    /// light regardless of which theme is active, the same way it would sit
    /// on a permanently-dark scrim in either light or dark mode. Matches the
    /// exact swatch `DarkPalette.textPrimary` already uses, so it reads as
    /// "this app's cream," not an arbitrary white.
    private static let heroTextColor = Color(hex: 0xF5F1EA)

    private func cover(topic: Topic) -> some View {
        ZStack(alignment: .bottomLeading) {
            TopicCoverThumbnail(urlString: topic.coverImageURL, placeholderFont: .largeTitle)
            // Transparent through the top two-thirds so the photo itself
            // stays vivid; darkens only where the title actually sits.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.04), location: 0.6),
                    .init(color: .black.opacity(0.68), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                if topic.visibility == .private {
                    Text("Private")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.22)))
                        .foregroundStyle(Self.heroTextColor)
                }
                Text(topic.title)
                    .font(.title2.bold())
                    .foregroundStyle(Self.heroTextColor)
                    // A soft, close shadow rather than a hard outline — legible
                    // over a busy photo without looking like a sticker.
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            }
            .padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // A soft, low, wide shadow under the whole card — a lifted-off-the-
        // page feel rather than a hard edge, matching "soft UI" without
        // reaching for a whole neumorphic inset/outset shadow pair, which
        // reads as busy under scroll and needs its own light-source
        // consistency this codebase doesn't otherwise establish.
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 20)
    }

    private func header(topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 6) {
                Text(topic.createdByName)
                Text("·").foregroundStyle(theme.textTertiary)
                Text("\(topic.videoCount) videos")
            }
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func startButton(topic: Topic) -> some View {
        NavigationLink {
            FeedView(mode: .topic(topicId: topicId, startingAtVideoId: viewModel.resumeVideoID), environment: environment, onExploreRequested: { dismiss() })
        } label: {
            Text(viewModel.hasStarted ? "Continue at video \(viewModel.resumeIndex + 1)" : "Start learning")
        }
        .buttonStyle(.shuiPill)
        .padding(.horizontal, 20)
        .simultaneousGesture(TapGesture().onEnded {
            AppAnalytics.logTopicStarted(topicId: topicId, categoryId: topic.categoryId)
        })
    }

    private func progressBlock(_ progress: TopicProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MasteryBar(percent: progress.masteryPercent)
            HStack(spacing: 16) {
                statPair(label: "Videos", value: "\(progress.videosCompleted)/\(progress.videosTotal)")
                statPair(label: "Quiz accuracy", value: accuracyLabel(progress))
                if let nextReview = viewModel.nextReviewDate {
                    statPair(label: "Next review", value: nextReview.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func accuracyLabel(_ progress: TopicProgress) -> String {
        guard progress.totalAnswers > 0 else { return "—" }
        let percent = Int((Double(progress.correctAnswers) / Double(progress.totalAnswers) * 100).rounded())
        return "\(percent)%"
    }

    private func statPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(theme.textSecondary)
        }
    }

    /// Collapsed to a few lines with a tap-to-expand affordance, so a long
    /// description doesn't push the video list — the thing you actually
    /// came here for — several screens down. A character-count threshold
    /// rather than measuring actual rendered truncation: simple, and short
    /// descriptions never show a toggle that would just collapse back to
    /// the exact same text it started as.
    @ViewBuilder
    private func descriptionSection(topic: Topic) -> some View {
        if !topic.description.isEmpty {
            let isLong = topic.description.count > 220
            VStack(alignment: .leading, spacing: 6) {
                Text((try? AttributedString(markdown: topic.description)) ?? AttributedString(topic.description))
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(isDescriptionExpanded || !isLong ? nil : 4)
                if isLong {
                    Button(isDescriptionExpanded ? "Show less" : "Read more") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDescriptionExpanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var videoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Videos")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    FeedView(mode: .topic(topicId: topicId, startingAtVideoId: video.id), environment: environment, onExploreRequested: { dismiss() })
                } label: {
                    VideoRow(index: index + 1, video: video, state: viewModel.state(for: video))
                }
                Divider().padding(.leading, 84)
            }
        }
    }
}

@MainActor
final class TopicPageViewModel: ObservableObject {
    @Published private(set) var topic: Topic?
    @Published private(set) var videos: [Video] = []
    @Published private(set) var topicProgress: TopicProgress?
    @Published private(set) var isLoading = true
    @Published var loadError: String?

    private var videoProgressByID: [String: VideoProgress] = [:]
    private let topicId: String
    private let environment: AppEnvironment

    init(topicId: String, environment: AppEnvironment) {
        self.topicId = topicId
        self.environment = environment
    }

    var hasStarted: Bool { videoProgressByID.values.contains { $0.completed } }

    /// First video that isn't yet completed, or the last video if
    /// everything's done — never past the end of the list.
    var resumeIndex: Int {
        let index = videos.firstIndex { video in
            guard let id = video.id else { return true }
            return videoProgressByID[id]?.completed != true
        }
        return index ?? max(videos.count - 1, 0)
    }

    var resumeVideoID: String? {
        videos.indices.contains(resumeIndex) ? videos[resumeIndex].id : nil
    }

    var nextReviewDate: Date? {
        videoProgressByID.values.map(\.dueDate).filter { $0 > Date() }.min()
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let topicTask = environment.topics.topic(id: topicId)
            async let videosTask = environment.videos.videos(inTopic: topicId)
            async let progressListTask = environment.progress.topicProgress()

            guard let fetchedTopic = try await topicTask else {
                loadError = "This topic couldn't be found."
                return
            }
            topic = fetchedTopic
            videos = try await videosTask
            topicProgress = try await progressListTask.first { $0.topicId == topicId }

            // Sequential, not parallel — topic video counts are small
            // (seeded content tops out at a few dozen), and this avoids
            // capturing this @MainActor object across task-group children.
            var progressByID: [String: VideoProgress] = [:]
            for video in videos {
                guard let id = video.id else { continue }
                if let progress = try? await environment.progress.videoProgress(videoId: id) {
                    progressByID[id] = progress
                }
            }
            videoProgressByID = progressByID
        } catch {
            loadError = error.localizedDescription
        }
    }

    func state(for video: Video) -> VideoLearnerState {
        guard let id = video.id, let progress = videoProgressByID[id] else { return .unwatched }
        if progress.quizPassed {
            return progress.dueDate <= Date() ? .needsReview : .quizPassed
        }
        return progress.completed ? .watched : .unwatched
    }
}

private struct VideoRow: View {
    @Environment(\.theme) private var theme
    let index: Int
    let video: Video
    let state: VideoLearnerState

    private var stateColor: Color {
        switch state {
        case .unwatched: return theme.textTertiary
        case .watched: return theme.accent
        case .quizPassed: return theme.success
        case .needsReview: return theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.surfaceSubtle)
                    .frame(width: 64, height: 40)
                Text("\(index)")
                    .font(.caption.bold())
                    .foregroundStyle(theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Image(systemName: state.systemImage)
                .foregroundStyle(stateColor)
                .accessibilityLabel(state.label)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var durationLabel: String {
        let minutes = Int(video.durationSeconds) / 60
        let seconds = Int(video.durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
