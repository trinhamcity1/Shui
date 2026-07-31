import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol QuizRepository {
    func quiz(forVideo videoId: String) async throws -> Quiz?
    func submit(videoId: String, answers: [QuizAttemptAnswer]) async throws -> QuizResult
    /// Creator-only (Phase 5 builds the real authoring UI around this) —
    /// exposed now so debug/test flows can attach a quiz to a video.
    func saveQuiz(videoId: String, questions: [QuizQuestionDraft], passThreshold: Double) async throws
}

struct FirestoreQuizRepository: QuizRepository {
    private let db: Firestore
    private let functions: Functions

    init(db: Firestore = FirebaseBootstrap.firestore, functions: Functions = FirebaseBootstrap.functions) {
        self.db = db
        self.functions = functions
    }

    func quiz(forVideo videoId: String) async throws -> Quiz? {
        try await db.collection("videos").document(videoId)
            .collection("quiz").document("current")
            .getDocument()
            .decodedIfExists()
    }

    /// Grading happens server-side in `submitQuizAttempt` — this never sees
    /// correct answers ahead of time and never grades on-device.
    func submit(videoId: String, answers: [QuizAttemptAnswer]) async throws -> QuizResult {
        let payload: [String: Any] = [
            "videoId": videoId,
            "answers": answers.map { ["questionId": $0.questionId, "selectedOptionIds": $0.selectedOptionIds] },
        ]
        let result = try await functions.httpsCallable("submitQuizAttempt").call(payload)
        guard JSONSerialization.isValidJSONObject(result.data) else {
            throw RepositoryError.malformedResponse
        }
        let data = try JSONSerialization.data(withJSONObject: result.data)
        return try JSONDecoder().decode(QuizResult.self, from: data)
    }

    func saveQuiz(videoId: String, questions: [QuizQuestionDraft], passThreshold: Double) async throws {
        let payload: [String: Any] = [
            "videoId": videoId,
            "passThreshold": passThreshold,
            "questions": questions.map { question in
                [
                    "id": question.id,
                    "prompt": question.prompt,
                    "options": question.options.map { ["id": $0.id, "text": $0.text] },
                    "correctOptionIds": question.correctOptionIds,
                    "requiredCorrectCount": question.requiredCorrectCount,
                    "explanation": question.explanation,
                    "orderIndex": question.orderIndex,
                ] as [String: Any]
            },
        ]
        _ = try await functions.httpsCallable("saveQuiz").call(payload)
    }
}

final class InMemoryQuizRepository: QuizRepository {
    var quizzes: [String: Quiz]
    var resultProvider: (String, [QuizAttemptAnswer]) -> QuizResult

    init(
        quizzes: [String: Quiz] = [:],
        resultProvider: @escaping (String, [QuizAttemptAnswer]) -> QuizResult = { _, _ in
            QuizResult(score: 1, passed: true, results: [])
        }
    ) {
        self.quizzes = quizzes
        self.resultProvider = resultProvider
    }

    func quiz(forVideo videoId: String) async throws -> Quiz? {
        quizzes[videoId]
    }

    func submit(videoId: String, answers: [QuizAttemptAnswer]) async throws -> QuizResult {
        resultProvider(videoId, answers)
    }

    func saveQuiz(videoId: String, questions: [QuizQuestionDraft], passThreshold: Double) async throws {
        quizzes[videoId] = Quiz(
            version: (quizzes[videoId]?.version ?? 0) + 1,
            questions: questions.map {
                QuizQuestion(
                    id: $0.id,
                    prompt: $0.prompt,
                    options: $0.options,
                    requiredCorrectCount: $0.requiredCorrectCount,
                    orderIndex: $0.orderIndex
                )
            },
            passThreshold: passThreshold,
            updatedBy: "preview-user",
            updatedAt: nil
        )
    }
}
