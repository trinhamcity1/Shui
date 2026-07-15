import Foundation

/// Points at a small backend *you* operate (e.g. a Cloudflare Worker or
/// Vercel function) that holds the real LLM API key server-side and forwards
/// a request to your model of choice. The iOS app deliberately never embeds
/// an LLM API key directly — a key bundled in a shipped binary can be
/// extracted from the IPA, which would leak it and let anyone spend your
/// API budget. Configure `TutorBackendURL` in Info.plist to enable this path;
/// leaving it unset (the MVP default) makes `TutorAIServiceFactory` fall
/// back to `RuleBasedTutorAI` instead.
enum TutorBackendConfig {
    static var endpointURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TutorBackendURL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        return url
    }
}

final class RemoteLLMTutorAI: TutorAIService {
    private let fallback: TutorAIService
    private let endpoint: URL
    private let session: URLSession

    init?(fallback: TutorAIService = RuleBasedTutorAI(), session: URLSession = .shared) {
        guard let endpoint = TutorBackendConfig.endpointURL else { return nil }
        self.endpoint = endpoint
        self.fallback = fallback
        self.session = session
    }

    func greeting(profile: UserProfile) async -> TutorMessage {
        if let message = await request(kind: "greeting", context: ["streak": "\(profile.currentStreak)"]) {
            return message
        }
        return await fallback.greeting(profile: profile)
    }

    func feedback(isCorrect: Bool, question: CivicsQuestion, profile: UserProfile) async -> TutorMessage {
        let context = [
            "isCorrect": "\(isCorrect)",
            "category": question.category.rawValue,
            "streak": "\(profile.currentStreak)",
        ]
        if let message = await request(kind: "feedback", context: context) {
            return message
        }
        return await fallback.feedback(isCorrect: isCorrect, question: question, profile: profile)
    }

    func sessionSummary(session log: SessionLog, profile: UserProfile) async -> TutorMessage {
        let context = [
            "questionsAnswered": "\(log.questionsAnswered)",
            "questionsCorrect": "\(log.questionsCorrect)",
            "streak": "\(profile.currentStreak)",
        ]
        if let message = await request(kind: "sessionSummary", context: context) {
            return message
        }
        return await fallback.sessionSummary(session: log, profile: profile)
    }

    func chatReply(question: String, lesson: LessonScript, history: [String], profile: UserProfile) async -> TutorMessage {
        let context = [
            "question": question,
            "lessonTitle": lesson.titleEN,
            "lessonQuestionIds": lesson.questionIds.map(String.init).joined(separator: ","),
            "history": history.suffix(5).joined(separator: "\n"),
        ]
        if let message = await request(kind: "chat", context: context) {
            return message
        }
        return await fallback.chatReply(question: question, lesson: lesson, history: history, profile: profile)
    }

    private struct RemoteResponse: Decodable {
        let textEN: String
        let textVI: String
        let emotion: CharacterEmotion
    }

    private func request(kind: String, context: [String: String]) async -> TutorMessage? {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 6
        let body: [String: Any] = ["kind": kind, "context": context]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        urlRequest.httpBody = payload

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(RemoteResponse.self, from: data)
            return TutorMessage(textEN: decoded.textEN, textVI: decoded.textVI, emotion: decoded.emotion)
        } catch {
            return nil
        }
    }
}
