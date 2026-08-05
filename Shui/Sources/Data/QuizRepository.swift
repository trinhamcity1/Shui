import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol QuizRepository {
    func quiz(forVideo videoId: String) async throws -> Quiz?
    func submit(videoId: String, answers: [QuizAttemptAnswer]) async throws -> QuizResult
    func saveQuiz(videoId: String, questions: [QuizQuestionDraft], passThreshold: Double) async throws

    // ---- Creator mode (Phase 5) ------------------------------------------

    /// Rejoins `quiz/current` with the owner-only `quiz/answers` doc into the
    /// editable draft shape. Rules let the video's owner (or an admin) read
    /// `answers` directly — this is the one legitimate reader besides
    /// `submitQuizAttempt`, and it's why editing an existing quiz doesn't
    /// need a dedicated callable. Returns `[]` when no quiz exists yet.
    func editableQuiz(forVideo videoId: String) async throws -> [QuizQuestionDraft]
    /// AI-drafted starting points, never saved automatically — the creator
    /// reviews and edits before anything is written.
    func suggestQuestions(videoId: String, count: Int) async throws -> [QuizQuestionDraft]
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

    func editableQuiz(forVideo videoId: String) async throws -> [QuizQuestionDraft] {
        let quizRef = db.collection("videos").document(videoId).collection("quiz")
        async let currentTask = quizRef.document("current").getDocument()
        async let answersTask = quizRef.document("answers").getDocument()
        let (currentSnap, answersSnap) = try await (currentTask, answersTask)
        guard let current = currentSnap.decodedIfExists(as: Quiz.self) else { return [] }

        // The answer key is keyed by question id rather than positionally —
        // `current.questions` is ordered by `orderIndex` while `answers` is
        // stored in save order, and assuming they line up would silently
        // attach the wrong explanation to the wrong question.
        let answersData = answersSnap.data()?["answers"] as? [[String: Any]] ?? []
        var keyed: [String: (correct: [String], explanation: String)] = [:]
        for entry in answersData {
            guard let id = entry["id"] as? String else { continue }
            keyed[id] = (
                correct: entry["correctOptionIds"] as? [String] ?? [],
                explanation: entry["explanation"] as? String ?? ""
            )
        }

        return current.questions
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { question in
                let answer = keyed[question.id]
                return QuizQuestionDraft(
                    id: question.id,
                    prompt: question.prompt,
                    options: question.options,
                    correctOptionIds: answer?.correct ?? [],
                    requiredCorrectCount: question.requiredCorrectCount,
                    explanation: answer?.explanation ?? "",
                    orderIndex: question.orderIndex
                )
            }
    }

    func suggestQuestions(videoId: String, count: Int) async throws -> [QuizQuestionDraft] {
        let result = try await functions.httpsCallable("suggestQuizQuestions").call([
            "videoId": videoId,
            "count": count,
        ])
        guard
            let data = result.data as? [String: Any],
            let rawQuestions = data["questions"] as? [[String: Any]]
        else {
            throw RepositoryError.malformedResponse
        }

        // Option ids are minted here rather than server-side: the model
        // returns option *text* plus a correct flag, and the ids only need to
        // be stable within this draft for the editor and `saveQuiz`.
        return rawQuestions.enumerated().compactMap { index, raw in
            guard
                let prompt = raw["prompt"] as? String,
                let explanation = raw["explanation"] as? String,
                let rawOptions = raw["options"] as? [[String: Any]]
            else { return nil }

            var options: [QuizOption] = []
            var correctIds: [String] = []
            for rawOption in rawOptions {
                guard let text = rawOption["text"] as? String else { continue }
                let optionId = UUID().uuidString
                options.append(QuizOption(id: optionId, text: text))
                if rawOption["isCorrect"] as? Bool == true { correctIds.append(optionId) }
            }
            guard options.count >= 2, !correctIds.isEmpty else { return nil }

            return QuizQuestionDraft(
                id: UUID().uuidString,
                prompt: prompt,
                options: options,
                correctOptionIds: correctIds,
                requiredCorrectCount: correctIds.count,
                explanation: explanation,
                orderIndex: index
            )
        }
    }
}

final class InMemoryQuizRepository: QuizRepository {
    var quizzes: [String: Quiz]
    /// Kept alongside `quizzes` because the real repository reads the answer
    /// key from a separate document — a fake that folded them together would
    /// hide the rejoin logic the editor depends on.
    var drafts: [String: [QuizQuestionDraft]] = [:]
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
        drafts[videoId] = questions
    }

    func editableQuiz(forVideo videoId: String) async throws -> [QuizQuestionDraft] {
        drafts[videoId] ?? []
    }

    func suggestQuestions(videoId: String, count: Int) async throws -> [QuizQuestionDraft] {
        let optionIds = (0..<3).map { _ in UUID().uuidString }
        return (0..<count).map { index in
            QuizQuestionDraft(
                id: UUID().uuidString,
                prompt: "Sample drafted question \(index + 1)?",
                options: [
                    QuizOption(id: optionIds[0], text: "The correct answer"),
                    QuizOption(id: optionIds[1], text: "A plausible distractor"),
                    QuizOption(id: optionIds[2], text: "Another distractor"),
                ],
                correctOptionIds: [optionIds[0]],
                requiredCorrectCount: 1,
                explanation: "This is where the explanation the learner reads would go.",
                orderIndex: index
            )
        }
    }
}
