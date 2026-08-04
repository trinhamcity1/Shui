import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol VideoRepository {
    func feed(categoryId: String?, limit: Int, after cursor: PageCursor?) async throws -> Page<Video>
    /// Same as `feed(categoryId:limit:after:)` but matching any of several
    /// categories at once — the feed's "new in your interests" bucket, where
    /// the learner has more than one chosen category.
    func feed(categoryIds: [String], limit: Int, after cursor: PageCursor?) async throws -> Page<Video>
    func videos(inTopic topicId: String) async throws -> [Video]
    func videos(withIds ids: [String]) async throws -> [Video]
    func video(id: String) async throws -> Video?
    func recordView(videoId: String, watchedSeconds: Double, completed: Bool) async throws
    /// Creator-only (Phase 5 builds the real authoring UI around this) —
    /// exposed now so debug/test flows can publish a video.
    func setVisibility(videoId: String, visibility: Video.Visibility) async throws
}

struct FirestoreVideoRepository: VideoRepository {
    private let db: Firestore
    private let auth: Auth
    private let functions: Functions

    init(
        db: Firestore = FirebaseBootstrap.firestore,
        auth: Auth = FirebaseBootstrap.auth,
        functions: Functions = FirebaseBootstrap.functions
    ) {
        self.db = db
        self.auth = auth
        self.functions = functions
    }

    func feed(categoryId: String?, limit: Int, after cursor: PageCursor?) async throws -> Page<Video> {
        var query: Query = db.collection("videos")
            .whereField("visibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("topicVisibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("status", isEqualTo: Video.Status.ready.rawValue)
            .whereField("isDeleted", isEqualTo: false)
        if let categoryId {
            query = query.whereField("categoryId", isEqualTo: categoryId)
        }
        query = query.order(by: "createdAt", descending: true).limit(to: limit)
        if let cursor {
            query = query.start(afterDocument: cursor.snapshot)
        }
        let snapshot = try await query.getDocuments()
        return Page(items: snapshot.decoded(), cursor: snapshot.documents.last.map(PageCursor.init))
    }

    func feed(categoryIds: [String], limit: Int, after cursor: PageCursor?) async throws -> Page<Video> {
        guard !categoryIds.isEmpty else { return Page(items: [], cursor: nil) }
        // Firestore's `in` accepts up to 30 values, comfortably above any
        // realistic interests list.
        var query: Query = db.collection("videos")
            .whereField("visibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("topicVisibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("status", isEqualTo: Video.Status.ready.rawValue)
            .whereField("isDeleted", isEqualTo: false)
            .whereField("categoryId", in: Array(categoryIds.prefix(30)))
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let cursor {
            query = query.start(afterDocument: cursor.snapshot)
        }
        let snapshot = try await query.getDocuments()
        return Page(items: snapshot.decoded(), cursor: snapshot.documents.last.map(PageCursor.init))
    }

    /// Public topic browsing only, per current (Phase 3) call sites — a
    /// creator/admin previewing their own unpublished videos within a topic
    /// is Phase 5's job and isn't wired up yet, so this mirrors
    /// `videoIsPublic` exactly rather than the fuller owner/admin rule.
    func videos(inTopic topicId: String) async throws -> [Video] {
        let snapshot = try await db.collection("videos")
            .whereField("topicId", isEqualTo: topicId)
            .whereField("visibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("topicVisibility", isEqualTo: Video.Visibility.public.rawValue)
            .whereField("status", isEqualTo: Video.Status.ready.rawValue)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "order")
            .getDocuments()
        return snapshot.decoded()
    }

    /// Small, exact-id lookups (a handful of due-for-review videos) — not a
    /// query, so no index concerns and no 30-item `in` cap to worry about.
    func videos(withIds ids: [String]) async throws -> [Video] {
        guard !ids.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: Video?.self) { group in
            for id in ids {
                group.addTask {
                    try await self.video(id: id)
                }
            }
            var results: [Video] = []
            for try await video in group {
                if let video {
                    results.append(video)
                }
            }
            return results
        }
    }

    func video(id: String) async throws -> Video? {
        try await db.collection("videos").document(id).getDocument().decodedIfExists()
    }

    /// Clients only ever write a view ping — `videos.viewCount` itself is
    /// maintained by the hourly `flushViewCounts` Function, never bumped
    /// directly from here.
    func recordView(videoId: String, watchedSeconds: Double, completed: Bool) async throws {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        try await db.collection("viewEvents").document().setData([
            "videoId": videoId,
            "uid": uid,
            "watchedSeconds": watchedSeconds,
            "completed": completed,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    func setVisibility(videoId: String, visibility: Video.Visibility) async throws {
        _ = try await functions.httpsCallable("setVideoVisibility").call([
            "videoId": videoId,
            "visibility": visibility.rawValue,
        ])
    }
}

final class InMemoryVideoRepository: VideoRepository {
    var videos: [Video]
    var recordedViews: [(videoId: String, watchedSeconds: Double, completed: Bool)] = []

    init(videos: [Video] = []) {
        self.videos = videos
    }

    private func isVisible(_ video: Video) -> Bool {
        video.status == .ready && video.visibility == .public && video.topicVisibility == .public && !video.isDeleted
    }

    func feed(categoryId: String?, limit: Int, after cursor: PageCursor?) async throws -> Page<Video> {
        let visible = videos.filter { isVisible($0) && (categoryId == nil || $0.categoryId == categoryId) }
        return Page(items: Array(visible.prefix(limit)), cursor: nil)
    }

    func feed(categoryIds: [String], limit: Int, after cursor: PageCursor?) async throws -> Page<Video> {
        let visible = videos.filter { isVisible($0) && categoryIds.contains($0.categoryId) }
        return Page(items: Array(visible.prefix(limit)), cursor: nil)
    }

    func videos(inTopic topicId: String) async throws -> [Video] {
        videos
            .filter { $0.topicId == topicId && $0.status == .ready && !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    func videos(withIds ids: [String]) async throws -> [Video] {
        videos.filter { video in video.id.map(ids.contains) ?? false }
    }

    func video(id: String) async throws -> Video? {
        videos.first { $0.id == id }
    }

    func recordView(videoId: String, watchedSeconds: Double, completed: Bool) async throws {
        recordedViews.append((videoId, watchedSeconds, completed))
    }

    func setVisibility(videoId: String, visibility: Video.Visibility) async throws {
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else { return }
        videos[index].visibility = visibility
    }
}
