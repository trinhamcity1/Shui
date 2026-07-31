import Foundation
import SwiftData

/// Owns the on-device SwiftData store.
///
/// Scope is deliberately narrow: **local preferences, a read cache, and an
/// offline queue.** Firestore is the source of truth for everything else. If
/// you find yourself reaching for this to answer "what is this learner's
/// progress", that belongs in a repository under `Sources/Data/` instead.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init(inMemory: Bool = false) {
        let schema = Schema([
            UserProfile.self,
            LessonComment.self,
            TutorChatMessage.self,
            PendingQuizAttempt.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    /// Test/preview helper — an isolated in-memory store.
    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    // MARK: - Local preferences

    /// Fetches the single local preferences record, creating one on first launch.
    func fetchOrCreateProfile() -> UserProfile {
        let context = container.mainContext
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    // MARK: - Comment cache

    /// Cached comments for a video, oldest first. Threading is assembled in the
    /// view layer to keep the predicate simple.
    func cachedComments(forVideo videoID: String) -> [LessonComment] {
        let predicate = #Predicate<LessonComment> { $0.videoID == videoID }
        var descriptor = FetchDescriptor<LessonComment>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// Comments composed offline and not yet accepted by the server.
    func pendingComments() -> [LessonComment] {
        let predicate = #Predicate<LessonComment> { $0.isPendingUpload }
        var descriptor = FetchDescriptor<LessonComment>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func insert(_ comment: LessonComment) {
        container.mainContext.insert(comment)
        try? container.mainContext.save()
    }

    // MARK: - AI thread cache

    func cachedChatMessages(forVideo videoID: String) -> [TutorChatMessage] {
        let predicate = #Predicate<TutorChatMessage> { $0.videoID == videoID }
        var descriptor = FetchDescriptor<TutorChatMessage>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func insert(_ message: TutorChatMessage) {
        container.mainContext.insert(message)
        try? container.mainContext.save()
    }

    // MARK: - Pending quiz attempt queue

    /// Oldest first, so a resubmission flush processes them in the order
    /// they were taken.
    func pendingQuizAttempts() -> [PendingQuizAttempt] {
        var descriptor = FetchDescriptor<PendingQuizAttempt>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func insert(_ attempt: PendingQuizAttempt) {
        container.mainContext.insert(attempt)
        try? container.mainContext.save()
    }

    func delete<T: PersistentModel>(_ object: T) {
        container.mainContext.delete(object)
        try? container.mainContext.save()
    }

    func save() {
        try? container.mainContext.save()
    }
}
