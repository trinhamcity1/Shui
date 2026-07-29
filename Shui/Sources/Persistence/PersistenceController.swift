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
            LessonComment.self,
            TutorChatMessage.self,
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

    /// Records a completed session. Kept here (rather than letting callers
    /// touch `container.mainContext` directly) so `ModelContext`/SwiftData
    /// APIs stay confined to this file.
    func logSession(_ log: SessionLog) {
        container.mainContext.insert(log)
        try? container.mainContext.save()
    }

    /// All comments for a lesson, oldest first. Threading (grouping replies
    /// under their parent) is done in the view layer to keep the SwiftData
    /// predicate simple.
    func comments(for lessonID: String) -> [LessonComment] {
        let predicate = #Predicate<LessonComment> { $0.lessonID == lessonID }
        var descriptor = FetchDescriptor<LessonComment>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func addComment(lessonID: String, authorName: String, text: String, parentID: UUID? = nil) {
        let comment = LessonComment(lessonID: lessonID, authorName: authorName, text: text, parentID: parentID)
        container.mainContext.insert(comment)
        try? container.mainContext.save()
    }

    /// AI tutor chat history for a lesson, oldest first.
    func chatMessages(for lessonID: String) -> [TutorChatMessage] {
        let predicate = #Predicate<TutorChatMessage> { $0.lessonID == lessonID }
        var descriptor = FetchDescriptor<TutorChatMessage>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func addChatMessage(lessonID: String, isUser: Bool, text: String) {
        let message = TutorChatMessage(lessonID: lessonID, isUser: isUser, text: text)
        container.mainContext.insert(message)
        try? container.mainContext.save()
    }

    func save() {
        try? container.mainContext.save()
    }
}
