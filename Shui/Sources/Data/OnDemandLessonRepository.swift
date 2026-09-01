import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Each case renders its own inline message — phase-07 §7's balance message
/// ("You need $X.XX of credit for a Y lesson") comes straight from the
/// server via `.insufficientCredit`, verbatim, never re-derived client-side.
enum OnDemandLessonError: LocalizedError {
    case notSignedIn
    case insufficientCredit(message: String)
    case invalidTopic(message: String)
    case network
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to create a lesson."
        case .insufficientCredit(let message), .invalidTopic(let message):
            return message
        case .network:
            return "Couldn't reach Shui. Check your connection and try again."
        case .unknown(let message):
            return message
        }
    }
}

protocol OnDemandLessonRepository {
    /// `videoId` is a fresh `videos/{id}` doc the moment this returns — the
    /// caller opens `environment.videos.video(id:)` (or just observes the
    /// same list this came from) to watch its `status` field advance.
    /// `status` here is `"ready"` immediately on a shared-cache hit
    /// (phase-07 §5) — the caller should treat that the same as any other
    /// ready lesson, not assume a fresh generation just because this call
    /// just happened.
    func createLesson(topic: String) async throws -> (videoId: String, status: String)
    /// Poll every ~3s while `status == "generating"` (§7) — this both reads
    /// GolpoAI's job status *and*, server-side, performs the
    /// watermark/cache-write side effects the first time it observes a
    /// terminal state, so it must be the one thing polling, not a plain
    /// Firestore listener racing it.
    func checkStatus(videoId: String) async throws -> (status: String, message: String?)
    func shareToSocial(videoId: String) async throws
}

struct FirestoreOnDemandLessonRepository: OnDemandLessonRepository {
    private let functions: Functions

    init(functions: Functions = FirebaseBootstrap.functions) {
        self.functions = functions
    }

    func createLesson(topic: String) async throws -> (videoId: String, status: String) {
        do {
            let result = try await functions.httpsCallable("createOnDemandLesson").call(["topic": topic])
            guard let data = result.data as? [String: Any],
                  let videoId = data["videoId"] as? String,
                  let status = data["status"] as? String else {
                throw RepositoryError.malformedResponse
            }
            return (videoId, status)
        } catch let error as NSError {
            throw Self.mapError(error)
        }
    }

    func checkStatus(videoId: String) async throws -> (status: String, message: String?) {
        do {
            let result = try await functions.httpsCallable("checkOnDemandLessonStatus").call(["videoId": videoId])
            guard let data = result.data as? [String: Any], let status = data["status"] as? String else {
                throw RepositoryError.malformedResponse
            }
            return (status, data["message"] as? String)
        } catch let error as NSError {
            throw Self.mapError(error)
        }
    }

    func shareToSocial(videoId: String) async throws {
        do {
            _ = try await functions.httpsCallable("shareLessonToSocial").call(["videoId": videoId])
        } catch let error as NSError {
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: NSError) -> OnDemandLessonError {
        guard error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) else {
            return .network
        }
        switch code {
        case .unauthenticated, .permissionDenied:
            return .notSignedIn
        case .resourceExhausted:
            return .insufficientCredit(message: error.localizedDescription)
        case .invalidArgument:
            return .invalidTopic(message: error.localizedDescription)
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown(error.localizedDescription)
        }
    }
}

/// Scripted — advances from "generating" to "ready" after `readyAfterPolls`
/// calls to `checkStatus`, so a preview or a UI test can exercise the
/// polling loop without a real backend.
final class InMemoryOnDemandLessonRepository: OnDemandLessonRepository {
    var readyAfterPolls = 2
    private var pollCounts: [String: Int] = [:]
    var sharedVideoIds: Set<String> = []

    func createLesson(topic: String) async throws -> (videoId: String, status: String) {
        (UUID().uuidString, "generating")
    }

    func checkStatus(videoId: String) async throws -> (status: String, message: String?) {
        let count = (pollCounts[videoId] ?? 0) + 1
        pollCounts[videoId] = count
        return (count >= readyAfterPolls ? "ready" : "generating", nil)
    }

    func shareToSocial(videoId: String) async throws {
        sharedVideoIds.insert(videoId)
    }
}
