import Foundation

/// One page of the vertical feed. A lesson can appear more than once (a
/// missed quiz resurfaces it later), so each appearance gets its own
/// identity — the `id` is the feed entry, `lessonID` is the content.
struct FeedEntry: Identifiable, Hashable {
    let id: UUID
    let lessonID: String

    init(lessonID: String) {
        self.id = UUID()
        self.lessonID = lessonID
    }
}

/// Pure ordering + resurfacing rules for the vertical feed. No I/O, so it's
/// directly unit-testable; `FeedViewModel` supplies the content and progress
/// snapshots. The learner's quiz history drives the order — this is the same
/// SM-2 state the session planner uses, surfaced TikTok-style instead of as
/// a fixed daily session.
enum FeedPlanner {
    /// Orders all lessons for the feed: lessons with a due (previously
    /// missed or scheduled) question first, then never-studied lessons,
    /// then already-learned ones — each group in stable question order.
    static func orderedLessons(
        questions: [CivicsQuestion],
        progressByID: [Int: QuestionProgress],
        lessonFor: (CivicsQuestion) -> LessonScript,
        now: Date = Date()
    ) -> [LessonScript] {
        var seenLessonIDs = Set<String>()
        var scored: [(lesson: LessonScript, bucket: Int, order: Int)] = []

        for question in questions {
            let lesson = lessonFor(question)
            guard seenLessonIDs.insert(lesson.id).inserted else { continue }

            let progresses = lesson.questionIds.compactMap { progressByID[$0] }
            let hasDue = progresses.contains { !$0.isNew && $0.dueDate <= now }
            let allNew = progresses.allSatisfy(\.isNew)
            let bucket = hasDue ? 0 : (allNew ? 1 : 2)
            scored.append((lesson, bucket, question.id))
        }

        return scored
            .sorted { ($0.bucket, $0.order) < ($1.bucket, $1.order) }
            .map(\.lesson)
    }

    /// Where a missed lesson should reappear: `gap` pages after the current
    /// one (per spec: "after viewing five new lessons"), clamped to the end
    /// of the feed.
    static func resurfaceIndex(afterCurrentIndex currentIndex: Int, feedCount: Int, gap: Int = 5) -> Int {
        min(max(currentIndex + gap, 0), feedCount)
    }
}
