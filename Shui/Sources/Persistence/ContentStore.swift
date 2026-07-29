import Foundation

/// Loads and indexes all bundled study content once at launch. Content is
/// static and ships inside the app bundle for the MVP — there is no remote
/// content sync yet (see README roadmap).
final class ContentStore {
    static let shared = ContentStore()

    let questions: [CivicsQuestion]
    let categories: [CategoryInfo]
    let lessons: [LessonScript]
    let currentOfficials: CurrentOfficialsConfig
    let character: TutorCharacter

    private let questionsByID: [Int: CivicsQuestion]
    private let lessonsByID: [String: LessonScript]
    private let categoriesByID: [QuestionCategory: CategoryInfo]

    private init() {
        let loadedQuestions = ContentRepository.loadJSON("civics_questions", as: [CivicsQuestion].self) ?? []
        let loadedCategories = ContentRepository.loadJSON("categories", as: [CategoryInfo].self) ?? []
        let loadedLessons = ContentRepository.loadJSON("lessons", as: [LessonScript].self) ?? []
        let loadedOfficials = ContentRepository.loadJSON("current_officials", as: CurrentOfficialsConfig.self)
        let loadedCharacter = ContentRepository.loadJSON("character", as: TutorCharacter.self)

        self.questions = loadedQuestions.sorted { $0.id < $1.id }
        self.categories = loadedCategories.sorted { $0.sortOrder < $1.sortOrder }
        self.lessons = loadedLessons
        self.currentOfficials = loadedOfficials ?? CurrentOfficialsConfig(
            lastUpdated: "1970-01-01", needsReviewAfterDays: 0,
            president: "—", vicePresident: "—", speakerOfHouse: "—", chiefJustice: "—", presidentParty: "—",
            sourceNote: "Bundled current_officials.json failed to load."
        )
        self.character = loadedCharacter ?? TutorCharacter(
            id: "lien", nameEN: "Ms. Lien", nameVI: "Chị Liên",
            bioEN: "", bioVI: "", greetings: [], correctAnswer: [], incorrectAnswer: [],
            streakEncouragement: [], sessionComplete: []
        )

        self.questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        self.lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        self.categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.category, $0) })
    }

    func question(id: Int) -> CivicsQuestion? { questionsByID[id] }

    func categoryInfo(for category: QuestionCategory) -> CategoryInfo? { categoriesByID[category] }

    func questions(in category: QuestionCategory) -> [CivicsQuestion] {
        questions.filter { $0.category == category }
    }

    /// Returns the question's hand-authored lesson if one exists, otherwise
    /// `nil` — callers should fall back to `FallbackLessonBuilder` so every
    /// one of the 100 questions still gets a narrated scene.
    func customLesson(for question: CivicsQuestion) -> LessonScript? {
        lessonsByID[question.lessonId]
    }

    func lesson(for question: CivicsQuestion) -> LessonScript {
        customLesson(for: question) ?? FallbackLessonBuilder.build(for: question)
    }

    /// Resolves the answer(s) a user should study for a question, filling in
    /// dynamic/user-specific values from the current officials config and the
    /// user's own local officials profile.
    func resolvedAnswers(for question: CivicsQuestion, localOfficials: LocalOfficialsProfile) -> [String] {
        switch question.dynamicType {
        case .none:
            return question.answersEN
        case .nationalOfficeholder:
            guard let role = question.officeholderRole else { return question.answersEN }
            let value = currentOfficials.value(forRole: role)
            return [value]
        case .userStateOfficeholder:
            switch question.officeholderRole {
            case "stateSenators":
                return [localOfficials.senator1, localOfficials.senator2].compactMap { $0 }
            case "representative":
                return [localOfficials.representative].compactMap { $0 }
            case "governor":
                return [localOfficials.governor].compactMap { $0 }
            default:
                return []
            }
        case .userStateCapital:
            return [localOfficials.stateCapital].compactMap { $0 }
        }
    }
}
