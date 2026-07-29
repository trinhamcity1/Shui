import Foundation

/// One question + lesson pairing scheduled into today's session.
struct SessionItem: Identifiable {
    let id: Int
    let question: CivicsQuestion
    let lesson: LessonScript
    let progress: QuestionProgress

    /// Rough playback + quiz time, used to keep sessions within the 5-10
    /// minute target described in the product brief.
    var estimatedSeconds: Double { lesson.totalDurationSeconds + 20 }
}

/// Builds today's 5-10 minute session out of the 100-question bank. This is
/// a pure function over content + progress snapshots (no I/O), which keeps
/// it easy to unit test and reuse both from the live app and from previews.
enum SessionPlanner {
    static func buildSession(
        allQuestions: [CivicsQuestion],
        allProgress: [QuestionProgress],
        targetMinutes: Int,
        now: Date = Date()
    ) -> [SessionItem] {
        let progressByID = Dictionary(uniqueKeysWithValues: allProgress.map { ($0.questionId, $0) })
        let budgetSeconds = Double(targetMinutes) * 60

        func progress(for question: CivicsQuestion) -> QuestionProgress {
            progressByID[question.id] ?? QuestionProgress(questionId: question.id)
        }

        let due = allQuestions
            .map { ($0, progress(for: $0)) }
            .filter { !$0.1.isNew && SpacedRepetitionScheduler.isDue($0.1, now: now) }
            .sorted { $0.1.dueDate < $1.1.dueDate }

        // Personalization: rank not-yet-studied questions by how weak the
        // learner currently is in that category, instead of always following
        // official question order 1...100.
        let categoryAccuracy: [QuestionCategory: Double] = Dictionary(grouping: allQuestions, by: \.category)
            .mapValues { questionsInCategory in
                let studied = questionsInCategory.compactMap { progressByID[$0.id] }.filter { !$0.isNew }
                guard !studied.isEmpty else { return 0.5 }
                return studied.reduce(0.0) { $0 + $1.accuracy } / Double(studied.count)
            }

        let newQuestions = allQuestions
            .map { ($0, progress(for: $0)) }
            .filter { $0.1.isNew }
            .sorted { lhs, rhs in
                let lhsAccuracy = categoryAccuracy[lhs.0.category] ?? 0.5
                let rhsAccuracy = categoryAccuracy[rhs.0.category] ?? 0.5
                if lhsAccuracy != rhsAccuracy { return lhsAccuracy < rhsAccuracy }
                return lhs.0.id < rhs.0.id
            }

        var items: [SessionItem] = []
        var usedSeconds = 0.0

        for (question, prog) in due + newQuestions {
            let lessonScript = ContentStore.shared.lesson(for: question)
            let item = SessionItem(id: question.id, question: question, lesson: lessonScript, progress: prog)
            if !items.isEmpty && usedSeconds + item.estimatedSeconds > budgetSeconds {
                break
            }
            items.append(item)
            usedSeconds += item.estimatedSeconds
        }

        return items
    }
}
