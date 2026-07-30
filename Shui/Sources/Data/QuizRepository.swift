import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol QuizRepository {
    func quiz(forVideo videoId: String) async throws -> Quiz?
    func submit(videoId: String, answers: [QuizAttemptAnswer]) async throws -> QuizResult
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
}
