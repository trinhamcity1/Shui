import Foundation

/// Self-assessment grade for a review, following the classic SM-2 scale
/// (a failed answer resets the interval; the rest scale it up).
enum ReviewGrade: Int {
    case again = 0
    case hard = 3
    case good = 4
    case easy = 5
}

/// The SM-2 state for one reviewable item. A plain value type with no storage
/// dependency, so the same math runs in the app, in tests, and (ported) in a
/// Cloud Function without three different notions of what the state is.
///
/// Mirrors the SM-2 fields on `users/{uid}/videoProgress/{videoId}`. Counters
/// like attempts and accuracy deliberately live *outside* this type — they
/// belong to progress reporting, not to the scheduling math.
struct ReviewState: Codable, Hashable {
    static let defaultEaseFactor = 2.5

    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date
    var lastReviewedAt: Date?

    init(
        easeFactor: Double = ReviewState.defaultEaseFactor,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        dueDate: Date,
        lastReviewedAt: Date? = nil
    ) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
    }

    /// A never-reviewed item. Due immediately, so anything the learner hasn't
    /// been quizzed on surfaces in the first review queue it qualifies for
    /// rather than waiting out an interval it never earned.
    static func new(now: Date = Date()) -> ReviewState {
        ReviewState(dueDate: now)
    }

    var isNew: Bool { repetitions == 0 && lastReviewedAt == nil }
}

/// A lightweight SM-2 spaced-repetition scheduler: every quiz result changes
/// when an item resurfaces, so two learners working through the same topic end
/// up with different review queues based on what they actually struggle with.
///
/// `schedule` is pure — it returns a new `ReviewState` rather than mutating a
/// stored object. The server-side copy of this math lives in
/// `functions/src/lib/sm2.ts`; the two must agree, and that agreement is what
/// the parity tests check.
enum SpacedRepetitionScheduler {
    static let minimumEaseFactor = 1.3

    static func schedule(_ state: ReviewState, grade: ReviewGrade, now: Date = Date()) -> ReviewState {
        var next = state
        let quality = Double(grade.rawValue)

        if grade == .again {
            next.repetitions = 0
            next.intervalDays = 1
        } else {
            switch state.repetitions {
            case 0: next.intervalDays = 1
            case 1: next.intervalDays = 6
            default: next.intervalDays = Int((Double(state.intervalDays) * state.easeFactor).rounded())
            }
            next.repetitions = state.repetitions + 1
        }

        let easeDelta = 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
        next.easeFactor = max(minimumEaseFactor, state.easeFactor + easeDelta)

        next.dueDate = Calendar.current.date(byAdding: .day, value: max(next.intervalDays, 1), to: now) ?? now
        next.lastReviewedAt = now
        return next
    }

    static func isDue(_ state: ReviewState, now: Date = Date()) -> Bool {
        state.dueDate <= now
    }
}
