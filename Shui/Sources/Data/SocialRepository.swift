import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol SocialRepository {
    func toggleLike(videoId: String) async throws -> Bool
    func likedVideos() async throws -> [LikedVideo]
    func comments(forVideo videoId: String, limit: Int, after cursor: PageCursor?) async throws -> Page<Comment>
    func postComment(videoId: String, text: String, parentId: String?) async throws
    func report(targetType: String, targetPath: String, reason: String, note: String?) async throws
}

struct FirestoreSocialRepository: SocialRepository {
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

    func toggleLike(videoId: String) async throws -> Bool {
        let result = try await functions.httpsCallable("toggleLike").call(["videoId": videoId])
        guard let data = result.data as? [String: Any], let liked = data["liked"] as? Bool else {
            throw RepositoryError.malformedResponse
        }
        return liked
    }

    func likedVideos() async throws -> [LikedVideo] {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try await db.collection("users").document(uid)
            .collection("likes")
            .order(by: "likedAt", descending: true)
            .getDocuments()
        return snapshot.decoded()
    }

    func comments(forVideo videoId: String, limit: Int, after cursor: PageCursor?) async throws -> Page<Comment> {
        var query: Query = db.collection("videos").document(videoId).collection("comments")
            .whereField("parentId", isEqualTo: NSNull())
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let cursor {
            query = query.start(afterDocument: cursor.snapshot)
        }
        let snapshot = try await query.getDocuments()
        return Page(items: snapshot.decoded(), cursor: snapshot.documents.last.map(PageCursor.init))
    }

    /// Rules require `likeCount`/`replyCount`/`reportCount` to be zero on
    /// create and reject guest (anonymous) authors entirely — this write
    /// will simply fail for a guest, which is the intended enforcement point.
    func postComment(videoId: String, text: String, parentId: String?) async throws {
        guard let user = auth.currentUser else { throw RepositoryError.notSignedIn }
        try await db.collection("videos").document(videoId).collection("comments").document().setData([
            "uid": user.uid,
            "authorName": user.displayName ?? "Learner",
            "authorPhotoURL": firestoreValue(user.photoURL?.absoluteString),
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "parentId": firestoreValue(parentId),
            "replyCount": 0,
            "likeCount": 0,
            "reportCount": 0,
            "isDeleted": false,
        ])
    }

    func report(targetType: String, targetPath: String, reason: String, note: String?) async throws {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        try await db.collection("reports").document().setData([
            "targetType": targetType,
            "targetPath": targetPath,
            "reporterUid": uid,
            "reason": reason,
            "note": firestoreValue(note),
            "createdAt": FieldValue.serverTimestamp(),
            "status": "open",
        ])
    }
}

final class InMemorySocialRepository: SocialRepository {
    var likedVideoIDs: Set<String> = []
    var likedVideoList: [LikedVideo]
    var commentsByVideo: [String: [Comment]]

    init(likedVideoList: [LikedVideo] = [], commentsByVideo: [String: [Comment]] = [:]) {
        self.likedVideoList = likedVideoList
        self.commentsByVideo = commentsByVideo
    }

    func toggleLike(videoId: String) async throws -> Bool {
        if likedVideoIDs.contains(videoId) {
            likedVideoIDs.remove(videoId)
            return false
        }
        likedVideoIDs.insert(videoId)
        return true
    }

    func likedVideos() async throws -> [LikedVideo] {
        likedVideoList
    }

    func comments(forVideo videoId: String, limit: Int, after cursor: PageCursor?) async throws -> Page<Comment> {
        Page(items: Array((commentsByVideo[videoId] ?? []).prefix(limit)), cursor: nil)
    }

    func postComment(videoId: String, text: String, parentId: String?) async throws {
        let comment = Comment(
            id: UUID().uuidString,
            uid: "preview-user",
            authorName: "Preview",
            authorPhotoURL: nil,
            authorHandle: nil,
            text: text,
            createdAt: Date(),
            editedAt: nil,
            parentId: parentId,
            replyCount: 0,
            likeCount: 0,
            isDeleted: false,
            reportCount: 0
        )
        commentsByVideo[videoId, default: []].insert(comment, at: 0)
    }

    func report(targetType: String, targetPath: String, reason: String, note: String?) async throws {}
}
