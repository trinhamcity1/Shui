import Foundation

/// Self-assessment grade for a review, following the classic SM-2 scale
/// (a failed answer resets the interval; the rest scale it up).
enum ReviewGrade: Int {
    case again = 0
    case hard = 3
    case good = 4
    case easy = 5
}

/// A lightweight SM-2 spaced-repetition scheduler. This is the concrete
/// mechanism behind "the character adapts to the user": every quiz result
/// changes when a question resurfaces, so two users studying the same 100
/// questions end up with two different daily sessions based on what they
/// actually struggle with.
enum SpacedRepetitionScheduler {
    static let minimumEaseFactor = 1.3

    static func schedule(_ progress: QuestionProgress, grade: ReviewGrade, now: Date = Date()) {
        let quality = Double(grade.rawValue)

        if grade == .again {
            progress.repetitions = 0
            progress.intervalDays = 1
            progress.timesIncorrect += 1
        } else {
            switch progress.repetitions {
            case 0: progress.intervalDays = 1
            case 1: progress.intervalDays = 6
            default: progress.intervalDays = Int((Double(progress.intervalDays) * progress.easeFactor).rounded())
            }
            progress.repetitions += 1
            progress.timesCorrect += 1
        }

        let easeDelta = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
        progress.easeFactor = max(minimumEaseFactor, progress.easeFactor + easeDelta)

        progress.dueDate = Calendar.current.date(byAdding: .day, value: max(progress.intervalDays, 1), to: now) ?? now
        progress.lastReviewedAt = now
    }

    static func isDue(_ progress: QuestionProgress, now: Date = Date()) -> Bool {
        progress.dueDate <= now
    }
}
