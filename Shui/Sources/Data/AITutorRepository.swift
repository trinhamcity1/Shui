import Foundation

/// Phase 4 implements this against `videos/{videoId}/aiThreads/{uid}` (a
/// grounded chat plus retention checks). Only the protocol exists in this
/// phase, so `AppEnvironment`'s shape doesn't change once that phase starts.
protocol AITutorRepository {
    func sendMessage(videoId: String, text: String, mode: String) async throws -> String
}

final class UnimplementedAITutorRepository: AITutorRepository {
    func sendMessage(videoId: String, text: String, mode: String) async throws -> String {
        throw RepositoryError.notImplemented
    }
}
