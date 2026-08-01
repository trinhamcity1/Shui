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
    @StateObject private var viewModel: TopicPageViewModel

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
                if !topic.description.isEmpty {
                    Text((try? AttributedString(markdown: topic.description)) ?? AttributedString(topic.description))
                        .font(.body)
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 20)
                }
                videoList
            }
            .padding(.bottom, 32)
        }
    }

    private func cover(topic: Topic) -> some View {
        RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(theme.surfaceSubtle)
            .frame(height: 180)
            .overlay(Image(systemName: "play.rectangle.fill").font(.largeTitle).foregroundStyle(theme.textTertiary))
    }

    private func header(topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(topic.title)
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                if topic.visibility == .private {
                    Text("Private")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.warning.opacity(0.18)))
                        .foregroundStyle(theme.warning)
                }
            }
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
            FeedView(mode: .topic(topicId: topicId, startingAtVideoId: viewModel.resumeVideoID), environment: environment)
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

    private var videoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Videos")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    FeedView(mode: .topic(topicId: topicId, startingAtVideoId: video.id), environment: environment)
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
