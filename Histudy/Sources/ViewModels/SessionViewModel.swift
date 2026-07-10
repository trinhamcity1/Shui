import Foundation

enum SessionPhase: Hashable {
    case lesson
    case quiz
    case summary
}

/// Drives one full daily session: lesson → quiz, repeated for every planned
/// item, then a summary. Owns the SM-2 grading + persistence side effects so
/// the views themselves stay dumb.
@MainActor
final class SessionViewModel: ObservableObject {
    let items: [SessionItem]
    @Published private(set) var index = 0
    @Published private(set) var phase: SessionPhase = .lesson
    @Published private(set) var lessonVM: LessonPlaybackViewModel?
    @Published private(set) var quizVM: QuizViewModel?
    @Published private(set) var feedbackMessage: TutorMessage?
    @Published private(set) var summaryMessage: TutorMessage?
    @Published private(set) var summaryLog: SessionLog?

    let narrator: SpeechNarrator
    private let tutorAI: TutorAIService
    private let profile: UserProfile

    private var questionIdsAnswered: [Int] = []
    private var lessonIdsWatched: [Int] = []
    private var correctCount = 0
    private let startedAt = Date()

    init(items: [SessionItem], profile: UserProfile, narrator: SpeechNarrator, tutorAI: TutorAIService) {
        self.items = items
        self.profile = profile
        self.narrator = narrator
        self.tutorAI = tutorAI
        if let first = items.first {
            lessonVM = LessonPlaybackViewModel(script: first.lesson, narrator: narrator)
        }
    }

    var currentItem: SessionItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var totalCount: Int { items.count }

    func lessonFinished() {
        guard let item = currentItem else { return }
        lessonIdsWatched.append(item.question.id)
        quizVM = QuizViewModel(
            question: item.question,
            allQuestions: ContentStore.shared.questions,
            localOfficials: profile.localOfficials
        )
        phase = .quiz
    }

    func quizAnswered() async {
        guard let item = currentItem, let quizVM else { return }
        questionIdsAnswered.append(item.question.id)

        let progress = PersistenceController.shared.fetchOrCreateProgress(for: item.question.id)
        progress.lessonWatched = true

        if quizVM.isAnswerable {
            if quizVM.isCorrect { correctCount += 1 }
            let grade: ReviewGrade = quizVM.isCorrect ? .good : .again
            SpacedRepetitionScheduler.schedule(progress, grade: grade)
            feedbackMessage = await tutorAI.feedback(isCorrect: quizVM.isCorrect, question: item.question, profile: profile)
        } else {
            feedbackMessage = nil
        }
        PersistenceController.shared.save()
    }

    func advance() async {
        index += 1
        feedbackMessage = nil
        if let next = currentItem {
            lessonVM = LessonPlaybackViewModel(script: next.lesson, narrator: narrator)
            quizVM = nil
            phase = .lesson
        } else {
            await finishSession()
        }
    }

    private func finishSession() async {
        let log = SessionLog(
            durationSeconds: Date().timeIntervalSince(startedAt),
            lessonIdsWatched: lessonIdsWatched,
            questionIds: questionIdsAnswered,
            questionsCorrect: correctCount
        )
        PersistenceController.shared.container.mainContext.insert(log)

        profile.totalLessonsCompleted += lessonIdsWatched.count
        profile.totalQuizzesTaken += questionIdsAnswered.count
        profile.registerSessionDay()
        PersistenceController.shared.save()

        summaryLog = log
        summaryMessage = await tutorAI.sessionSummary(session: log, profile: profile)
        phase = .summary
    }
}
