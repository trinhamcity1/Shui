import Foundation

/// Offline, deterministic (well, randomized-but-local) tutor responses drawn
/// from `character.json`. Zero latency, zero cost, works with no network —
/// the right default for a two-week MVP, and the fallback for
/// `RemoteLLMTutorAI` if a backend call ever fails.
final class RuleBasedTutorAI: TutorAIService {
    private let character: TutorCharacter

    init(character: TutorCharacter = ContentStore.shared.character) {
        self.character = character
    }

    func greeting(profile: UserProfile) async -> TutorMessage {
        pick(character.greetings, emotion: .happy)
    }

    func feedback(isCorrect: Bool, question: CivicsQuestion, profile: UserProfile) async -> TutorMessage {
        isCorrect ? pick(character.correctAnswer, emotion: .celebrating)
                  : pick(character.incorrectAnswer, emotion: .encouraging)
    }

    func sessionSummary(session: SessionLog, profile: UserProfile) async -> TutorMessage {
        profile.currentStreak >= 3
            ? pick(character.streakEncouragement, emotion: .celebrating)
            : pick(character.sessionComplete, emotion: .happy)
    }

    /// Offline chat: retrieval over the lesson's own civics content. The
    /// user's question is keyword-matched against every question this
    /// lesson covers; the best match's Vietnamese explanation (plus the
    /// English quick fact) is the reply. Not generative — but grounded,
    /// instant, free, and it never fabricates civics facts. The remote
    /// LLM path (`RemoteLLMTutorAI`) layers real generation on top when a
    /// backend is configured.
    func chatReply(question: String, lesson: LessonScript, history: [String], profile: UserProfile) async -> TutorMessage {
        let coveredQuestions = lesson.questionIds.compactMap { ContentStore.shared.question(id: $0) }
        let queryTokens = tokens(in: question)

        var best: (question: CivicsQuestion, score: Int)?
        for candidate in coveredQuestions {
            let haystack = tokens(in: candidate.questionEN)
                .union(tokens(in: candidate.quickFactEN))
                .union(tokens(in: candidate.answersEN.joined(separator: " ")))
            let score = queryTokens.intersection(haystack).count
            if score > (best?.score ?? 0) {
                best = (candidate, score)
            }
        }

        if let best {
            return TutorMessage(
                textEN: best.question.quickFactEN,
                textVI: best.question.explanationVI,
                emotion: .thinking
            )
        }

        // Nothing matched — restate what this lesson teaches instead of
        // guessing at an answer we don't have grounded content for.
        let fallbackVI = "Bài học này nói về: \(lesson.titleVI). "
            + (coveredQuestions.first.map { "Điểm chính: \($0.explanationVI)" } ?? "")
        let fallbackEN = "This lesson covers: \(lesson.titleEN). "
            + (coveredQuestions.first.map { "Key point: \($0.quickFactEN)" } ?? "")
        return TutorMessage(textEN: fallbackEN, textVI: fallbackVI, emotion: .encouraging)
    }

    private func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )
    }

    private func pick(_ lines: [BilingualLine], emotion: CharacterEmotion) -> TutorMessage {
        guard let line = lines.randomElement() else {
            return TutorMessage(textEN: "Great work!", textVI: "Làm tốt lắm!", emotion: emotion)
        }
        return TutorMessage(textEN: line.textEN, textVI: line.textVI, emotion: emotion)
    }
}
