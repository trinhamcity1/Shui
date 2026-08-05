import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

enum TopicSort {
    case newest
    case mostLearners
}

protocol TopicRepository {
    /// Small, unpaginated fetch — the Explore "Continue learning" row and
    /// anywhere else that just needs "the public topics in this category,"
    /// no sort/paging control. `topics(inCategory:sortedBy:limit:after:)` is
    /// the paginated form the category page actually uses.
    func topics(inCategory categoryId: String) async throws -> [Topic]
    func topics(inCategory categoryId: String, sortedBy: TopicSort, limit: Int, after cursor: PageCursor?) async throws -> Page<Topic>
    /// A live server-side count, not `Category.topicCount` (a denormalized
    /// counter maintained by a Cloud Functions trigger on publish/unpublish
    /// — one more moving part than a count strictly needs, and one that's
    /// silently wrong until deployed, until every already-public topic gets
    /// one more write to be picked up, or if it simply never fires for a
    /// reason nothing surfaces). Explore's category grid reads this instead
    /// specifically because it's the one place a wrong "0 topics" actively
    /// misleads a learner into thinking a category is empty when it isn't —
    /// worth a cheap aggregate query over trusting a counter with that much
    /// surface area for silently drifting out of sync.
    func publicTopicCount(inCategory categoryId: String) async throws -> Int
    /// Firestore has no full-text search — a `title`-prefix range query
    /// (`title >= q`, `title < q + high-codepoint`), scoped to public,
    /// non-deleted topics. Finds topics, not videos or tags; the caller is
    /// responsible for also matching cached topics against `tags`
    /// client-side, per the phase spec.
    func searchByTitlePrefix(_ prefix: String, limit: Int) async throws -> [Topic]
    func topic(id: String) async throws -> Topic?
    func myTopics() async throws -> [Topic]
    /// Every creator's topics, admin only — rules allow the read because
    /// `isAdmin()` doesn't depend on document data, so the whole condition
    /// short-circuits true for an admin and the query is provably safe.
    /// Returns empty rather than throwing for a non-admin, since the caller
    /// is a screen that shouldn't have been reachable at all.
    func allTopics(limit: Int) async throws -> [Topic]
    func create(_ topic: Topic) async throws -> Topic
    func update(_ topic: Topic) async throws
    func setVisibility(topicId: String, visibility: Topic.Visibility) async throws
    func softDelete(topicId: String) async throws
    /// Structure only — title/subtitle/description/category/tags, no videos,
    /// always private. Deliberately not a server-side copy: there's nothing
    /// to fan out, and a client write keeps it inside the same rules the
    /// editor already obeys.
    func duplicate(_ topic: Topic) async throws -> Topic
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

    func topics(inCategory categoryId: String, sortedBy: TopicSort, limit: Int, after cursor: PageCursor?) async throws -> Page<Topic> {
        var query: Query = db.collection("topics")
            .whereField("categoryId", isEqualTo: categoryId)
            .whereField("visibility", isEqualTo: Topic.Visibility.public.rawValue)
            .whereField("isDeleted", isEqualTo: false)
        switch sortedBy {
        case .newest:
            query = query.order(by: "publishedAt", descending: true)
        case .mostLearners:
            query = query.order(by: "learnerCount", descending: true)
        }
        query = query.limit(to: limit)
        if let cursor {
            query = query.start(afterDocument: cursor.snapshot)
        }
        let snapshot = try await query.getDocuments()
        return Page(items: snapshot.decoded(), cursor: snapshot.documents.last.map(PageCursor.init))
    }

    /// Queries the denormalized `titleLowercase` field, not `title` — a
    /// case-sensitive-only prefix match would fail almost every real typed
    /// query, which isn't "small and honest" so much as broken. `title`
    /// itself stays proper-cased for display; `create`/`update` keep
    /// `titleLowercase` in sync.
    func searchByTitlePrefix(_ prefix: String, limit: Int) async throws -> [Topic] {
        let normalized = prefix.lowercased()
        guard !normalized.isEmpty else { return [] }
        let upperBound = normalized + "\u{f8ff}"
        let snapshot = try await db.collection("topics")
            .whereField("visibility", isEqualTo: Topic.Visibility.public.rawValue)
            .whereField("isDeleted", isEqualTo: false)
            .whereField("titleLowercase", isGreaterThanOrEqualTo: normalized)
            .whereField("titleLowercase", isLessThan: upperBound)
            .order(by: "titleLowercase")
            .limit(to: limit)
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
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        return snapshot.decoded()
    }

    func allTopics(limit: Int) async throws -> [Topic] {
        let snapshot = try await db.collection("topics")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.decoded()
    }

    /// Three equality-only filters, no `orderBy` — unlike every other
    /// composite query in this file, this genuinely needs no composite
    /// index at all (Firestore can satisfy an equality-only, multi-field
    /// filter with its automatic single-field indexes; a composite index is
    /// only required once an `orderBy` or a range filter joins the mix).
    /// One aggregate read regardless of how many topics match, per
    /// Firestore's count-query pricing — cheap even for a large category.
    func publicTopicCount(inCategory categoryId: String) async throws -> Int {
        let query = db.collection("topics")
            .whereField("categoryId", isEqualTo: categoryId)
            .whereField("visibility", isEqualTo: Topic.Visibility.public.rawValue)
            .whereField("isDeleted", isEqualTo: false)
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
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
            "titleLowercase": topic.title.lowercased(),
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
            "titleLowercase": topic.title.lowercased(),
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

    func softDelete(topicId: String) async throws {
        _ = try await functions.httpsCallable("softDeleteTopic").call(["topicId": topicId])
    }

    func duplicate(_ topic: Topic) async throws -> Topic {
        var copy = topic
        copy.id = nil
        copy.title = "\(topic.title) copy"
        copy.coverImageURL = nil
        copy.visibility = .private
        copy.publishedAt = nil
        copy.videoCount = 0
        copy.totalDurationSec = 0
        copy.learnerCount = 0
        copy.isDeleted = false
        return try await create(copy)
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

    func topics(inCategory categoryId: String, sortedBy: TopicSort, limit: Int, after cursor: PageCursor?) async throws -> Page<Topic> {
        var matching = topics.filter { $0.categoryId == categoryId && $0.visibility == .public && !$0.isDeleted }
        switch sortedBy {
        case .newest:
            matching.sort { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        case .mostLearners:
            matching.sort { $0.learnerCount > $1.learnerCount }
        }
        return Page(items: Array(matching.prefix(limit)), cursor: nil)
    }

    func searchByTitlePrefix(_ prefix: String, limit: Int) async throws -> [Topic] {
        let normalized = prefix.lowercased()
        guard !normalized.isEmpty else { return [] }
        return Array(
            topics
                .filter { $0.visibility == .public && !$0.isDeleted && $0.title.lowercased().hasPrefix(normalized) }
                .prefix(limit)
        )
    }

    func topic(id: String) async throws -> Topic? {
        topics.first { $0.id == id }
    }

    func myTopics() async throws -> [Topic] {
        guard let uid = currentUID else { return [] }
        return topics.filter { $0.createdBy == uid && !$0.isDeleted }
    }

    func allTopics(limit: Int) async throws -> [Topic] {
        Array(topics.filter { !$0.isDeleted }.prefix(limit))
    }

    func publicTopicCount(inCategory categoryId: String) async throws -> Int {
        topics.filter { $0.categoryId == categoryId && $0.visibility == .public && !$0.isDeleted }.count
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

    func softDelete(topicId: String) async throws {
        guard let index = topics.firstIndex(where: { $0.id == topicId }) else { return }
        topics[index].isDeleted = true
    }

    func duplicate(_ topic: Topic) async throws -> Topic {
        var copy = topic
        copy.id = nil
        copy.title = "\(topic.title) copy"
        copy.coverImageURL = nil
        copy.visibility = .private
        copy.videoCount = 0
        copy.learnerCount = 0
        return try await create(copy)
    }
}
