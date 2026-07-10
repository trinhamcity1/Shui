import Foundation
import SwiftData

/// Owns the on-device SwiftData store for user progress. Study content
/// itself (`ContentStore`) is bundled JSON and never written to; only the
/// user's own profile and progress live in this local database.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init(inMemory: Bool = false) {
        let schema = Schema([
            UserProfile.self,
            QuestionProgress.self,
            SessionLog.self,
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

    /// Fetches the single local profile, creating one on first launch.
    func fetchOrCreateProfile() -> UserProfile {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Fetches (or lazily creates) the progress record for a question.
    func fetchOrCreateProgress(for questionId: Int) -> QuestionProgress {
        let context = container.mainContext
        let predicate = #Predicate<QuestionProgress> { $0.questionId == questionId }
        var descriptor = FetchDescriptor<QuestionProgress>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let progress = QuestionProgress(questionId: questionId)
        context.insert(progress)
        try? context.save()
        return progress
    }

    func allProgress() -> [QuestionProgress] {
        (try? container.mainContext.fetch(FetchDescriptor<QuestionProgress>())) ?? []
    }

    func save() {
        try? container.mainContext.save()
    }
}
