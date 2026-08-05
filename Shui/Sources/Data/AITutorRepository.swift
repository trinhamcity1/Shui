import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// What `aiTutorMessage` returns once it finishes — the transcript itself
/// arrives separately and earlier, token by token, via `observeThread`'s
/// live Firestore listener; this is just the final confirmation plus the
/// structured hints (chips, retention verdict) in case the UI's own
/// listener hasn't caught up to the just-finalized document yet.
struct AITutorSendResult: Decodable {
    let messageId: String
    let text: String
    let suggestedReplies: [String]
    let retentionAssessment: AIRetentionAssessment?
}

/// Each case renders its own specific inline message per the phase spec —
/// never a generic "Something went wrong."
enum AITutorError: LocalizedError {
    case notSignedIn
    case rateLimited(resetAt: Date?)
    case network
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to use the AI tutor."
        case .rateLimited(let resetAt):
            guard let resetAt else { return "You've reached the AI tutor's limit for now. Try again later." }
            return "You've reached the AI tutor's limit for now. Try again after \(resetAt.formatted(date: .omitted, time: .shortened))."
        case .network:
            return "Couldn't reach the AI tutor. Check your connection and try again."
        case .unknown(let message):
            return message
        }
    }
}

protocol AITutorRepository {
    /// Live updates to a thread's messages, oldest first. The underlying
    /// Firestore listener is removed automatically when the enclosing
    /// `Task` is cancelled (stream termination), not something the caller
    /// manages directly.
    func observeThread(videoId: String) -> AsyncThrowingStream<[AIMessage], Error>
    func sendMessage(videoId: String, mode: AIThreadMode, text: String?, isSessionStart: Bool) async throws -> AITutorSendResult
}

struct FirestoreAITutorRepository: AITutorRepository {
    private let db: Firestore
    private let functions: Functions
    private let auth: Auth

    init(
        db: Firestore = FirebaseBootstrap.firestore,
        functions: Functions = FirebaseBootstrap.functions,
        auth: Auth = FirebaseBootstrap.auth
    ) {
        self.db = db
        self.functions = functions
        self.auth = auth
    }

    func observeThread(videoId: String) -> AsyncThrowingStream<[AIMessage], Error> {
        AsyncThrowingStream { continuation in
            guard let uid = auth.currentUser?.uid else {
                continuation.finish(throwing: AITutorError.notSignedIn)
                return
            }
            let query = db.collection("videos").document(videoId)
                .collection("aiThreads").document(uid)
                .collection("messages")
                .order(by: "createdAt")
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                let messages = snapshot.documents.compactMap { try? $0.data(as: AIMessage.self) }
                continuation.yield(messages)
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func sendMessage(videoId: String, mode: AIThreadMode, text: String?, isSessionStart: Bool) async throws -> AITutorSendResult {
        var payload: [String: Any] = [
            "videoId": videoId,
            "mode": mode.rawValue,
            "isSessionStart": isSessionStart,
        ]
        if let text { payload["text"] = text }

        do {
            let result = try await functions.httpsCallable("aiTutorMessage").call(payload)
            guard JSONSerialization.isValidJSONObject(result.data) else {
                throw RepositoryError.malformedResponse
            }
            let data = try JSONSerialization.data(withJSONObject: result.data)
            return try JSONDecoder().decode(AITutorSendResult.self, from: data)
        } catch let error as NSError {
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: NSError) -> AITutorError {
        guard error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) else {
            return .network
        }
        switch code {
        case .unauthenticated, .permissionDenied:
            return .notSignedIn
        case .resourceExhausted:
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            let resetAtString = details?["resetAt"] as? String
            return .rateLimited(resetAt: resetAtString.flatMap(Self.parseISO8601))
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown(error.localizedDescription)
        }
    }

    /// `usage.resetAt.toISOString()` server-side (JS) always includes
    /// milliseconds (`.SSS`) — `ISO8601DateFormatter()`'s *default*
    /// configuration doesn't parse that and silently returns nil, which is
    /// why the rate-limit message was falling back to "try again later"
    /// with no actual time. Try with fractional seconds first, then
    /// without, rather than assuming the server's exact format forever.
    private static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions.insert(.withFractionalSeconds)
        if let date = withFractional.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string)
    }
}

/// Scripted, in-memory — previews and anything that just needs *a* tutor
/// conversation without a real backend. Not a network stub: `sendMessage`
/// synthesizes an assistant reply and appends it to the same array
/// `observeThread` streams from, so the preview experience matches the real
/// one (session-start opener, suggested replies, mode divider) without any
/// Firebase dependency.
final class InMemoryAITutorRepository: AITutorRepository {
    private var messagesByVideo: [String: [AIMessage]] = [:]
    private var continuationsByVideo: [String: AsyncThrowingStream<[AIMessage], Error>.Continuation] = [:]

    func observeThread(videoId: String) -> AsyncThrowingStream<[AIMessage], Error> {
        AsyncThrowingStream { continuation in
            continuationsByVideo[videoId] = continuation
            continuation.yield(messagesByVideo[videoId] ?? [])
        }
    }

    func sendMessage(videoId: String, mode: AIThreadMode, text: String?, isSessionStart: Bool) async throws -> AITutorSendResult {
        var thread = messagesByVideo[videoId] ?? []
        if !isSessionStart, let text {
            thread.append(AIMessage(role: .user, mode: mode, text: text, status: nil))
        }
        let replyText = isSessionStart
            ? (mode == .discuss ? "Ready to dig into this lesson? Ask me anything." : "First question: what was the main idea of this video?")
            : "That's roughly right — the lesson frames it a bit differently, but you've got the core idea."
        let suggestions = ["Tell me more", "What's the key takeaway?", "Quiz me on this"]
        let assistant = AIMessage(
            role: .assistant,
            mode: mode,
            text: replyText,
            status: .complete,
            suggestedReplies: suggestions,
            retentionAssessment: nil,
            promptVersion: "preview"
        )
        thread.append(assistant)
        messagesByVideo[videoId] = thread
        continuationsByVideo[videoId]?.yield(thread)
        return AITutorSendResult(messageId: UUID().uuidString, text: replyText, suggestedReplies: suggestions, retentionAssessment: nil)
    }
}
