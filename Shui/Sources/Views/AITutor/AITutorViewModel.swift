import Foundation

/// Owns the live thread listener and message sending. One instance per
/// `AITutorSheet` presentation, scoped to a single video.
@MainActor
final class AITutorViewModel: ObservableObject {
    @Published private(set) var messages: [AIMessage] = []
    @Published private(set) var isSendingSessionStart = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    /// Set only for `.rateLimited` failures, alongside `errorMessage` — kept
    /// as a raw `Date` (not baked into the message string) so the view can
    /// render a live countdown via SwiftUI's `Text(_:style: .timer)`
    /// instead of a static "try again at 8:45 PM" that goes stale the
    /// moment it's drawn.
    @Published private(set) var rateLimitResetAt: Date?

    /// A plain `didSet`, not a computed binding with a separate "switch"
    /// method — the segmented control in `AITutorSheet` binds directly to
    /// this, and a mode that has no messages yet automatically triggers its
    /// own opener, matching "switching mid-thread inserts a divider rather
    /// than clearing history" from the phase spec.
    @Published var mode: AIThreadMode = .discuss {
        didSet {
            guard oldValue != mode, !hasStarted(mode: mode) else { return }
            Task { await sendSessionStart(mode: mode) }
        }
    }

    let videoId: String
    private let environment: AppEnvironment
    private var observeTask: Task<Void, Never>?

    init(videoId: String, environment: AppEnvironment) {
        self.videoId = videoId
        self.environment = environment
    }

    var suggestedReplies: [String] {
        guard let last = messages.last, last.role == .assistant, last.status == .complete else { return [] }
        return last.suggestedReplies ?? []
    }

    func start() async {
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            guard let self else { return }
            var hasCheckedInitialStart = false
            do {
                for try await updated in self.environment.aiTutor.observeThread(videoId: self.videoId) {
                    self.messages = updated
                    // Gated on the *first* real snapshot, not a fixed delay
                    // — otherwise reopening a video with real history could
                    // race a redundant session-start against the thread
                    // that's still loading.
                    if !hasCheckedInitialStart {
                        hasCheckedInitialStart = true
                        if !self.hasStarted(mode: self.mode) {
                            await self.sendSessionStart(mode: self.mode)
                        }
                    }
                }
            } catch {
                self.apply(error, fallback: "Couldn't load this conversation.")
            }
        }
    }

    func stop() {
        observeTask?.cancel()
        observeTask = nil
    }

    func hasStarted(mode: AIThreadMode) -> Bool {
        messages.contains { $0.mode == mode }
    }

    func sendSessionStart(mode: AIThreadMode) async {
        isSendingSessionStart = true
        clearError()
        defer { isSendingSessionStart = false }
        do {
            _ = try await environment.aiTutor.sendMessage(videoId: videoId, mode: mode, text: nil, isSessionStart: true)
        } catch {
            apply(error, fallback: "Couldn't reach the AI tutor.")
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        clearError()
        defer { isSending = false }
        do {
            _ = try await environment.aiTutor.sendMessage(videoId: videoId, mode: mode, text: trimmed, isSessionStart: false)
        } catch {
            apply(error, fallback: "Couldn't reach the AI tutor.")
        }
    }

    private func clearError() {
        errorMessage = nil
        rateLimitResetAt = nil
    }

    private func apply(_ error: Error, fallback: String) {
        guard let tutorError = error as? AITutorError else {
            errorMessage = fallback
            rateLimitResetAt = nil
            return
        }
        if case .rateLimited(let resetAt) = tutorError {
            rateLimitResetAt = resetAt
            errorMessage = resetAt == nil ? tutorError.errorDescription : nil
        } else {
            errorMessage = tutorError.errorDescription
            rateLimitResetAt = nil
        }
    }
}
