import Foundation

/// Local, unsent edits for the creator's two long-form editors.
///
/// "Losing a quiz you typed on the subway is unacceptable"
/// (prompts/phase-05-creator-mode.md §7). Every keystroke in the topic and
/// quiz editors is mirrored here; the copy is cleared only once a server
/// write actually succeeds. On reopening an editor, a newer local draft is
/// offered rather than silently applied — silently overwriting what the
/// server has would be its own kind of data loss when the same topic was
/// edited from another device.
///
/// `UserDefaults` rather than SwiftData, following `BlockedUsersStore`:
/// these are small, single-device, and disposable. Uploads deliberately have
/// no equivalent — they need connectivity and the upload flow says so.
enum CreatorDraftStore {
    private static let topicPrefix = "com.shui.creator.topicDraft."
    private static let quizPrefix = "com.shui.creator.quizDraft."

    // MARK: - Topic drafts

    struct TopicDraft: Codable {
        var title: String
        var subtitle: String
        var description: String
        var categoryId: String
        var tags: [String]
        var savedAt: Date
    }

    /// `nil` id means the unsaved "new topic" slot — there's only ever one,
    /// since the editor for a new topic is modal.
    private static func topicKey(_ topicId: String?) -> String {
        topicPrefix + (topicId ?? "__new__")
    }

    static func saveTopicDraft(_ draft: TopicDraft, topicId: String?) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: topicKey(topicId))
    }

    static func topicDraft(topicId: String?) -> TopicDraft? {
        guard let data = UserDefaults.standard.data(forKey: topicKey(topicId)) else { return nil }
        return try? JSONDecoder().decode(TopicDraft.self, from: data)
    }

    static func clearTopicDraft(topicId: String?) {
        UserDefaults.standard.removeObject(forKey: topicKey(topicId))
    }

    // MARK: - Quiz drafts

    struct QuizDraft: Codable {
        var questions: [QuizQuestionDraft]
        var passThreshold: Double
        var savedAt: Date
    }

    static func saveQuizDraft(_ draft: QuizDraft, videoId: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: quizPrefix + videoId)
    }

    static func quizDraft(videoId: String) -> QuizDraft? {
        guard let data = UserDefaults.standard.data(forKey: quizPrefix + videoId) else { return nil }
        return try? JSONDecoder().decode(QuizDraft.self, from: data)
    }

    static func clearQuizDraft(videoId: String) {
        UserDefaults.standard.removeObject(forKey: quizPrefix + videoId)
    }
}
