import Combine
import Foundation

/// Drives the vertical lesson feed: builds the ordered entry list, tracks
/// the visible page, grades quiz answers into the SM-2 engine, resurfaces
/// missed lessons a few pages later, and triggers the sign-in prompt after
/// two completed lessons.
///
/// Performance note: the spec's prefetch/cache/progressive-playback
/// requirements are trivially satisfied here because lesson "videos" are
/// procedurally rendered from bundled JSON — there is no network fetch to
/// hide. When real streamed video (S3 + AVPlayer) lands, this is the place
/// to add an URL prefetch window around `currentEntryID`.
@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var entries: [FeedEntry] = []
    @Published var currentEntryID: UUID?
    @Published var showSignInPrompt = false

    private var lessonsByID: [String: LessonScript] = [:]
    private var hasPromptedSignIn = false

    func load() {
        let questions = ContentStore.shared.questions
        let progressByID = Dictionary(
            uniqueKeysWithValues: PersistenceController.shared.allProgress().map { ($0.questionId, $0) }
        )
        let ordered = FeedPlanner.orderedLessons(
            questions: questions,
            progressByID: progressByID,
            lessonFor: { ContentStore.shared.lesson(for: $0) }
        )
        lessonsByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        entries = ordered.map { FeedEntry(lessonID: $0.id) }
        currentEntryID = entries.first?.id
    }

    func lesson(for entry: FeedEntry) -> LessonScript? {
        lessonsByID[entry.lessonID]
    }

    /// The quiz questions for a feed page: up to two of the lesson's
    /// covered civics questions, per the one-to-two-questions spec.
    func quizQuestions(for entry: FeedEntry) -> [CivicsQuestion] {
        guard let lesson = lessonsByID[entry.lessonID] else { return [] }
        return lesson.questionIds.prefix(2).compactMap { ContentStore.shared.question(id: $0) }
    }

    /// Grades one answered question into the spaced-repetition engine. A
    /// wrong answer also re-queues this lesson ~5 pages ahead so it comes
    /// back with a freshly shuffled option set.
    func recordAnswer(entry: FeedEntry, questionID: Int, wasCorrect: Bool) {
        let progress = PersistenceController.shared.fetchOrCreateProgress(for: questionID)
        progress.lessonWatched = true
        SpacedRepetitionScheduler.schedule(progress, grade: wasCorrect ? .good : .again)
        PersistenceController.shared.save()

        if !wasCorrect {
            resurface(entry: entry)
        }
    }

    /// Called when a page's full lesson+quiz cycle completes; drives the
    /// "sign in after two lessons" gate.
    func lessonCompleted(profile: UserProfile) {
        profile.feedLessonsCompleted += 1
        profile.totalLessonsCompleted += 1
        profile.registerSessionDay()
        PersistenceController.shared.save()

        if profile.feedLessonsCompleted >= 2, !profile.isSignedIn, !hasPromptedSignIn {
            hasPromptedSignIn = true
            showSignInPrompt = true
        }
    }

    private func resurface(entry: FeedEntry) {
        let currentIndex = entries.firstIndex { $0.id == (currentEntryID ?? entry.id) } ?? 0
        let insertAt = FeedPlanner.resurfaceIndex(afterCurrentIndex: currentIndex, feedCount: entries.count)
        entries.insert(FeedEntry(lessonID: entry.lessonID), at: insertAt)
    }
}
