import FirebaseFirestore
import Foundation

protocol VideoRepository {
    func feed(categoryId: String?, limit: Int, after cursor: DocumentSnapshot?) async throws -> Page<Video>
    func videos(inTopic topicId: String) async throws -> [Video]
    func video(id: String) async throws -> Video?
}

struct FirestoreVideoRepository: VideoRepository {
    private let db: Firestore

    init(db: Firestore = FirebaseBootstrap.firestore) {
        self.db = db
    }

    func feed(categoryId: String?, limit: Int, after cursor: DocumentSnapshot?) async throws -> Page<Video> {
        var query: Query = db.collection("videos")
            .whereField("topicVisibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("status", isEqualTo: Video.Status.ready.rawValue)
            .whereField("isDeleted", isEqualTo: false)
        if let categoryId {
            query = query.whereField("categoryId", isEqualTo: categoryId)
        }
        query = query.order(by: "createdAt", descending: true).limit(to: limit)
        if let cursor {
            query = query.start(afterDocument: cursor)
        }
        let snapshot = try await query.getDocuments()
        return Page(items: snapshot.decoded(), cursor: snapshot.documents.last)
    }

    func videos(inTopic topicId: String) async throws -> [Video] {
        let snapshot = try await db.collection("videos")
            .whereField("topicId", isEqualTo: topicId)
            .whereField("status", isEqualTo: Video.Status.ready.rawValue)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "order")
            .getDocuments()
        return snapshot.decoded()
    }

    func video(id: String) async throws -> Video? {
        try await db.collection("videos").document(id).getDocument().decodedIfExists()
    }
}

final class InMemoryVideoRepository: VideoRepository {
    var videos: [Video]

    init(videos: [Video] = []) {
        self.videos = videos
    }

    func feed(categoryId: String?, limit: Int, after cursor: DocumentSnapshot?) async throws -> Page<Video> {
        let visible = videos.filter {
            $0.status == .ready && $0.visibility == .public && $0.topicVisibility == .public && !$0.isDeleted
                && (categoryId == nil || $0.categoryId == categoryId)
        }
        return Page(items: Array(visible.prefix(limit)), cursor: nil)
    }

    func videos(inTopic topicId: String) async throws -> [Video] {
        videos
            .filter { $0.topicId == topicId && $0.status == .ready && !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    func video(id: String) async throws -> Video? {
        videos.first { $0.id == id }
    }
}
