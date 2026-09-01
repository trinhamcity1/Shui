import SwiftUI

/// phase-07 §9 — "What do you want to learn today?", a single text field, a
/// generate button, and a visible credit balance. One screen that changes
/// shape as generation progresses, same discipline as
/// `VideoUploadFlowView`'s upload stages.
enum LessonCreationStage: Equatable {
    case idle
    case generating
    case ready(videoId: String)
    case failed(message: String, canRetry: Bool)

    var isBusy: Bool {
        self == .generating
    }
}

@MainActor
final class CreateLessonViewModel: ObservableObject {
    @Published var topic: String
    @Published private(set) var stage: LessonCreationStage = .idle
    @Published private(set) var wallet: Wallet?

    private let environment: AppEnvironment
    private var pollTask: Task<Void, Never>?

    init(environment: AppEnvironment, initialTopic: String = "") {
        self.environment = environment
        self.topic = initialTopic
    }

    var trimmedTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSubmit: Bool { !trimmedTopic.isEmpty && !stage.isBusy }

    var tierInfo: TierInfo { TierInfo.info(for: wallet?.tier ?? .free) }

    /// Shown next to the balance so "why does a 30-second lesson cost
    /// nothing?" and "why does this one cost $8?" both have an answer
    /// on-screen before the learner taps Generate.
    var costPreviewLabel: String? {
        guard let wallet else { return nil }
        if wallet.tier == .free && !wallet.hasUsedFreeLesson {
            return "Your first lesson is free."
        }
        let cents = Int((tierInfo.lessonMinutes * 400).rounded())
        return "This will use \((Double(cents) / 100).formatted(.currency(code: "USD"))) of your balance."
    }

    func loadWallet() async {
        wallet = try? await environment.billing.wallet()
    }

    func generate() {
        let topic = trimmedTopic
        guard !topic.isEmpty else { return }
        stage = .generating
        Task {
            do {
                let (videoId, status) = try await environment.onDemandLessons.createLesson(topic: topic)
                if status == "ready" {
                    stage = .ready(videoId: videoId)
                } else {
                    startPolling(videoId: videoId)
                }
            } catch {
                stage = .failed(message: error.localizedDescription, canRetry: true)
            }
            await loadWallet()
        }
    }

    private func startPolling(videoId: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            // GolpoAI reports no granular progress (phase-07 §9) — this
            // loop's only job is to notice a terminal state, not to show one
            // faster than it actually arrives.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let (status, message) = try await self.environment.onDemandLessons.checkStatus(videoId: videoId)
                    switch status {
                    case "ready":
                        self.stage = .ready(videoId: videoId)
                        return
                    case "failed":
                        self.stage = .failed(message: message ?? "Something went wrong generating this lesson.", canRetry: true)
                        return
                    default:
                        continue
                    }
                } catch {
                    self.stage = .failed(message: error.localizedDescription, canRetry: true)
                    return
                }
            }
        }
    }

    func retry() {
        stage = .idle
        generate()
    }

    func cancelPolling() {
        pollTask?.cancel()
    }
}

struct CreateLessonView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateLessonViewModel
    @State private var readyVideo: Video?
    @FocusState private var topicFieldFocused: Bool

    init(environment: AppEnvironment, initialTopic: String = "") {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: CreateLessonViewModel(environment: environment, initialTopic: initialTopic))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New lesson")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.cancel) {
                            viewModel.cancelPolling()
                            dismiss()
                        }
                    }
                }
                .interactiveDismissDisabled(viewModel.stage.isBusy)
                .task { await viewModel.loadWallet() }
                .shuiShellBackground()
        }
        .fullScreenCover(item: $readyVideo) { video in
            FeedView(mode: .videoList(videos: [video]), environment: environment)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stage {
        case .idle:
            form
        case .generating:
            generatingView
        case .ready(let videoId):
            readyView(videoId: videoId)
        case .failed(let message, let canRetry):
            failedView(message: message, canRetry: canRetry)
        }
    }

    private var form: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Text("What do you want to learn today?")
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                TextField("Type a topic…", text: $viewModel.topic, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surfaceSubtle))
                    .focused($topicFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { if viewModel.canSubmit { viewModel.generate() } }
            }
            .padding(.horizontal, 24)

            if let costPreview = viewModel.costPreviewLabel {
                VStack(spacing: 4) {
                    Text(costPreview)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                    if let wallet = viewModel.wallet, wallet.tier != .free || wallet.hasUsedFreeLesson {
                        Text("Balance: \(wallet.creditBalanceDisplay) · \(viewModel.tierInfo.displayName)")
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            Button("Generate") { viewModel.generate() }
                .buttonStyle(.shuiPill)
                .disabled(!viewModel.canSubmit)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .onAppear { topicFieldFocused = true }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Creating your lesson…")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text("This usually takes a minute or two. You can leave this screen — it'll keep generating in the background.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readyView(videoId: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.success)
            Text("Your lesson is ready")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Button("Watch it") {
                Task {
                    readyVideo = try? await environment.videos.video(id: videoId)
                }
            }
            .buttonStyle(.shuiPill)
            .padding(.horizontal, 24)
            Button(Strings.done) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String, canRetry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.error)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if canRetry {
                Button(Strings.retry) { viewModel.retry() }
                    .buttonStyle(.shuiPill)
                    .padding(.horizontal, 24)
            }
            Button(Strings.cancel, role: .cancel) { dismiss() }
                .buttonStyle(.shuiPillOutline)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
