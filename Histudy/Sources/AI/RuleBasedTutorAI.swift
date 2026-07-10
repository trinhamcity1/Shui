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

    private func pick(_ lines: [BilingualLine], emotion: CharacterEmotion) -> TutorMessage {
        guard let line = lines.randomElement() else {
            return TutorMessage(textEN: "Great work!", textVI: "Làm tốt lắm!", emotion: emotion)
        }
        return TutorMessage(textEN: line.textEN, textVI: line.textVI, emotion: emotion)
    }
}
