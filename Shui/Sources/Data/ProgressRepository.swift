import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol ProgressRepository {
    func topicProgress() async throws -> [TopicProgress]
    func videoProgress(videoId: String) async throws -> VideoProgress?
    func dueForReview(limit: Int) async throws -> [VideoProgress]
    func markCompleted(videoId: String, watchedSeconds: Double) async throws
}

struct FirestoreProgressRepository: ProgressRepository {
    private let db: Firestore
    private let functions: Functions
    private let auth: Auth

    init(
        db: Firestore = FirebaseBootstrap.firestore,
        functions: Functions = FirebaseBootstrap.functions,
        auth: Auth = FirebaseBootstrap.auth
    ) {
        self.db = db
        self.functions = functions
        self.auth = auth
    }

    func topicProgress() async throws -> [TopicProgress] {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try await db.collection("users").document(uid)
            .collection("topicProgress")
            .order(by: "lastActivityAt", descending: true)
            .getDocuments()
        return snapshot.decoded()
    }

    func videoProgress(videoId: String) async throws -> VideoProgress? {
        guard let uid = auth.currentUser?.uid else { return nil }
        return try await db.collection("users").document(uid)
            .collection("videoProgress").document(videoId)
            .getDocument()
            .decodedIfExists()
    }

    func dueForReview(limit: Int) async throws -> [VideoProgress] {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try await db.collection("users").document(uid)
            .collection("videoProgress")
            .whereField("dueDate", isLessThanOrEqualTo: Timestamp(date: Date()))
            .order(by: "dueDate")
            .limit(to: limit)
            .getDocuments()
        return snapshot.decoded()
    }

    func markCompleted(videoId: String, watchedSeconds: Double) async throws {
        _ = try await functions.httpsCallable("markVideoCompleted").call([
            "videoId": videoId,
            "watchedSeconds": watchedSeconds,
        ])
    }
}

final class InMemoryProgressRepository: ProgressRepository {
    var topicProgressList: [TopicProgress]
    var videoProgressByID: [String: VideoProgress]

    init(topicProgressList: [TopicProgress] = [], videoProgressByID: [String: VideoProgress] = [:]) {
        self.topicProgressList = topicProgressList
        self.videoProgressByID = videoProgressByID
    }

    func topicProgress() async throws -> [TopicProgress] {
        topicProgressList
    }

    func videoProgress(videoId: String) async throws -> VideoProgress? {
        videoProgressByID[videoId]
    }

    func dueForReview(limit: Int) async throws -> [VideoProgress] {
        Array(videoProgressByID.values.filter { $0.dueDate <= Date() }.prefix(limit))
    }

    func markCompleted(videoId: String, watchedSeconds: Double) async throws {
        guard var existing = videoProgressByID[videoId] else { return }
        existing.watchedSeconds = max(existing.watchedSeconds, watchedSeconds)
        videoProgressByID[videoId] = existing
    }
}
