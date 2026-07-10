import Foundation

/// The "AI-powered personalization" surface: short, in-character messages
/// reacting to what the learner just did. Two implementations exist —
/// `RuleBasedTutorAI` (default, fully offline) and `RemoteLLMTutorAI`
/// (optional, backend-proxied) — see `TutorAIServiceFactory`.
protocol TutorAIService {
    func greeting(profile: UserProfile) async -> TutorMessage
    func feedback(isCorrect: Bool, question: CivicsQuestion, profile: UserProfile) async -> TutorMessage
    func sessionSummary(session: SessionLog, profile: UserProfile) async -> TutorMessage
}

enum TutorAIServiceFactory {
    /// Prefers a backend-proxied LLM tutor if `TutorBackendURL` is configured
    /// in Info.plist; otherwise falls back to the offline rule-based tutor.
    /// The MVP ships with no backend configured, so this returns the
    /// rule-based implementation by default — a deliberate, honest scoping
    /// choice (see README) rather than embedding an LLM API key in the app.
    static func make() -> TutorAIService {
        if let remote = RemoteLLMTutorAI() {
            return remote
        }
        return RuleBasedTutorAI()
    }
}
