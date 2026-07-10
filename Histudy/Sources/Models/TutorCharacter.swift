import Foundation

/// A bilingual line of dialogue.
struct BilingualLine: Codable, Hashable {
    let textEN: String
    let textVI: String

    func text(for language: AppLanguage) -> String {
        language == .vietnamese ? textVI : textEN
    }
}

/// The MVP ships a single tutor character, "Ms. Lien" — a warm, patient
/// guide voiced and drawn entirely in code (vector SwiftUI shapes + AVSpeech
/// narration), so the app needs no external character art or audio assets.
struct TutorCharacter: Codable {
    let id: String
    let nameEN: String
    let nameVI: String
    let bioEN: String
    let bioVI: String
    let greetings: [BilingualLine]
    let correctAnswer: [BilingualLine]
    let incorrectAnswer: [BilingualLine]
    let streakEncouragement: [BilingualLine]
    let sessionComplete: [BilingualLine]

    func name(for language: AppLanguage) -> String {
        language == .vietnamese ? nameVI : nameEN
    }
}

/// Facial expression driving `TutorCharacterView`.
enum CharacterEmotion: String, Codable, Hashable {
    case neutral, happy, encouraging, thinking, celebrating
}

/// A message the character "speaks", produced by either the rule-based or
/// remote AI tutor implementation. See `Sources/AI/TutorAIService.swift`.
struct TutorMessage: Hashable {
    let textEN: String
    let textVI: String
    let emotion: CharacterEmotion

    func text(for language: AppLanguage) -> String {
        language == .vietnamese ? textVI : textEN
    }
}
