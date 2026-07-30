import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol TopicRepository {
    func topics(inCategory categoryId: String) async throws -> [Topic]
    func topic(id: String) async throws -> Topic?
    func myTopics() async throws -> [Topic]
    func create(_ topic: Topic) async throws -> Topic
    func update(_ topic: Topic) async throws
    func setVisibility(topicId: String, visibility: Topic.Visibility) async throws
}

struct FirestoreTopicRepository: TopicRepository {
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

    func topics(inCategory categoryId: String) async throws -> [Topic] {
        let snapshot = try await db.collection("topics")
            .whereField("categoryId", isEqualTo: categoryId)
            .whereField("visibility", isEqualTo: Topic.Visibility.public.rawValue)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "publishedAt", descending: true)
            .getDocuments()
        return snapshot.decoded()
    }

    func topic(id: String) async throws -> Topic? {
        try await db.collection("topics").document(id).getDocument().decodedIfExists()
    }

    func myTopics() async throws -> [Topic] {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try await db.collection("topics")
            .whereField("createdBy", isEqualTo: uid)
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        return snapshot.decoded()
    }

    /// Writes only the fields rules permit a creator to set on create: the
    /// visibility/publishedAt/counters that follow are Function-only, so
    /// this ignores whatever those fields are set to on `topic` and always
    /// starts a topic private with zeroed counters.
    func create(_ topic: Topic) async throws -> Topic {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        let ref = db.collection("topics").document()
        try await ref.setData([
            "title": topic.title,
            "subtitle": topic.subtitle,
            "description": topic.description,
            "categoryId": topic.categoryId,
            "coverImageURL": firestoreValue(topic.coverImageURL),
            "visibility": Topic.Visibility.private.rawValue,
            "createdBy": uid,
            "createdByName": topic.createdByName,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "publishedAt": NSNull(),
            "videoCount": 0,
            "totalDurationSec": 0,
            "learnerCount": 0,
            "tags": topic.tags,
            "isDeleted": false,
        ])
        var payload = topic
        payload.id = ref.documentID
        payload.createdBy = uid
        payload.visibility = .private
        payload.videoCount = 0
        payload.totalDurationSec = 0
        payload.learnerCount = 0
        payload.isDeleted = false
        return payload
    }

    /// Plain-field edits only. Visibility, `publishedAt`, and the
    /// denormalized counters go through `setVisibility` (a callable) or a
    /// Function trigger — rules reject them here regardless.
    func update(_ topic: Topic) async throws {
        guard let id = topic.id else { return }
        try await db.collection("topics").document(id).updateData([
            "title": topic.title,
            "subtitle": topic.subtitle,
            "description": topic.description,
            "categoryId": topic.categoryId,
            "coverImageURL": firestoreValue(topic.coverImageURL),
            "tags": topic.tags,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    func setVisibility(topicId: String, visibility: Topic.Visibility) async throws {
        _ = try await functions.httpsCallable("setTopicVisibility").call([
            "topicId": topicId,
            "visibility": visibility.rawValue,
        ])
    }
}

final class InMemoryTopicRepository: TopicRepository {
    var topics: [Topic]
    var currentUID: String?

    init(topics: [Topic] = [], currentUID: String? = "preview-user") {
        self.topics = topics
        self.currentUID = currentUID
    }

    func topics(inCategory categoryId: String) async throws -> [Topic] {
        topics.filter { $0.categoryId == categoryId && $0.visibility == .public && !$0.isDeleted }
    }

    func topic(id: String) async throws -> Topic? {
        topics.first { $0.id == id }
    }

    func myTopics() async throws -> [Topic] {
        guard let uid = currentUID else { return [] }
        return topics.filter { $0.createdBy == uid }
    }

    func create(_ topic: Topic) async throws -> Topic {
        var payload = topic
        payload.id = payload.id ?? UUID().uuidString
        payload.visibility = .private
        topics.append(payload)
        return payload
    }

    func update(_ topic: Topic) async throws {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
    }

    func setVisibility(topicId: String, visibility: Topic.Visibility) async throws {
        guard let index = topics.firstIndex(where: { $0.id == topicId }) else { return }
        topics[index].visibility = visibility
    }
}
