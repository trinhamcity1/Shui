import Foundation

/// How a question's correct answer should be resolved at display time.
///
/// Several official USCIS answers are time-sensitive (the sitting President)
/// or depend on where the applicant lives (their own Senators, Governor,
/// state capital). Baking a specific name into the app would silently go
/// stale, so those answers are resolved at runtime instead of stored as
/// static strings in the question bank.
enum DynamicAnswerType: String, Codable, Hashable {
    /// Static answer, bundled directly in `answersEN`.
    case none
    /// Resolved from `CurrentOfficialsConfig` (president, VP, Speaker, Chief Justice, party).
    case nationalOfficeholder
    /// Resolved from the user's own profile (Senators, Representative, Governor).
    case userStateOfficeholder
    /// Resolved from the static `state_capitals.json` lookup using the user's state.
    case userStateCapital
}

/// One question from the official 100-question USCIS civics test.
struct CivicsQuestion: Codable, Identifiable, Hashable {
    let id: Int
    let category: QuestionCategory
    let questionEN: String
    /// Acceptable correct answers. Empty when `dynamicType != .none`.
    let answersEN: [String]
    /// How many distinct answers the applicant must name (USCIS uses 1, 2, or 3).
    let requiredAnswerCount: Int
    /// Vietnamese explanation with narrative/mnemonic context, shown before the quiz.
    let explanationVI: String
    /// Short English callout used in the flashcard-style fallback lesson.
    let quickFactEN: String
    let dynamicType: DynamicAnswerType
    let officeholderRole: String?
    /// The `LessonScript.id` that teaches this question, whether a flagship
    /// narrative lesson or the generic fallback covers it.
    let lessonId: String

    var isDynamic: Bool { dynamicType != .none }
}
