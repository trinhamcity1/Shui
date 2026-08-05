import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol SocialRepository {
    func toggleLike(videoId: String) async throws -> Bool
    func likedVideos() async throws -> [LikedVideo]
    /// A private bookmark, not a public engagement signal — see
    /// `SavedVideo` for why this has no counter to keep in sync, unlike
    /// `toggleLike`.
    func toggleSave(videoId: String) async throws -> Bool
    func savedVideos() async throws -> [SavedVideo]
    func comments(forVideo videoId: String, limit: Int, after cursor: PageCursor?) async throws -> Page<Comment>
    /// Up to `limit` replies to one top-level comment, oldest first (reply
    /// threads read like a conversation, unlike the newest-first top level).
    func replies(forComment commentId: String, videoId: String, limit: Int) async throws -> [Comment]
    func postComment(videoId: String, text: String, parentId: String?) async throws
    /// Direct client write, not a callable — rules already permit exactly
    /// this (author, within 15 minutes, touching only text/editedAt).
    func editComment(videoId: String, commentId: String, text: String) async throws
    func deleteComment(videoId: String, commentId: String) async throws
    func toggleCommentLike(videoId: String, commentId: String) async throws -> Bool
    func isCommentLiked(videoId: String, commentId: String) async throws -> Bool
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

    func toggleSave(videoId: String) async throws -> Bool {
        let result = try await functions.httpsCallable("toggleSave").call(["videoId": videoId])
        guard let data = result.data as? [String: Any], let saved = data["saved"] as? Bool else {
            throw RepositoryError.malformedResponse
        }
        return saved
    }

    func savedVideos() async throws -> [SavedVideo] {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try await db.collection("users").document(uid)
            .collection("savedVideos")
            .order(by: "savedAt", descending: true)
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

    func replies(forComment commentId: String, videoId: String, limit: Int) async throws -> [Comment] {
        let snapshot = try await db.collection("videos").document(videoId).collection("comments")
            .whereField("parentId", isEqualTo: commentId)
            .order(by: "createdAt")
            .limit(to: limit)
            .getDocuments()
        return snapshot.decoded()
    }

    /// Rules require `likeCount`/`replyCount`/`reportCount` to be zero on
    /// create and reject guest (anonymous) authors entirely — this write
    /// will simply fail for a guest, which is the intended enforcement point.
    /// `authorName`/`authorPhotoURL`/`authorHandle` are denormalized at
    /// write time so rendering a comment list never needs a per-author
    /// lookup — the tradeoff is they go stale if the author edits their
    /// profile later, same tradeoff already accepted for `authorName`.
    func postComment(videoId: String, text: String, parentId: String?) async throws {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        let user: UserAccount? = try? await db.collection("users").document(uid).getDocument().decodedIfExists()
        let handle: String? = (user?.handle.isEmpty ?? true) ? nil : user?.handle
        try await db.collection("videos").document(videoId).collection("comments").document().setData([
            "uid": uid,
            "authorName": user?.displayName ?? auth.currentUser?.displayName ?? "Learner",
            "authorPhotoURL": firestoreValue(user?.photoURL),
            "authorHandle": firestoreValue(handle),
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "parentId": firestoreValue(parentId),
            "replyCount": 0,
            "likeCount": 0,
            "reportCount": 0,
            "isDeleted": false,
        ])
    }

    func editComment(videoId: String, commentId: String, text: String) async throws {
        try await db.collection("videos").document(videoId).collection("comments").document(commentId).updateData([
            "text": text,
            "editedAt": FieldValue.serverTimestamp(),
        ])
    }

    func deleteComment(videoId: String, commentId: String) async throws {
        _ = try await functions.httpsCallable("softDeleteComment").call(["videoId": videoId, "commentId": commentId])
    }

    func toggleCommentLike(videoId: String, commentId: String) async throws -> Bool {
        let result = try await functions.httpsCallable("toggleCommentLike").call(["videoId": videoId, "commentId": commentId])
        guard let data = result.data as? [String: Any], let liked = data["liked"] as? Bool else {
            throw RepositoryError.malformedResponse
        }
        return liked
    }

    func isCommentLiked(videoId: String, commentId: String) async throws -> Bool {
        guard let uid = auth.currentUser?.uid else { return false }
        let snapshot = try await db.collection("users").document(uid).collection("commentLikes").document(commentId).getDocument()
        return snapshot.exists
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
    var likedCommentIDs: Set<String> = []
    var likedVideoList: [LikedVideo]
    var savedVideoIDs: Set<String> = []
    var savedVideoList: [SavedVideo]
    var commentsByVideo: [String: [Comment]]

    init(likedVideoList: [LikedVideo] = [], savedVideoList: [SavedVideo] = [], commentsByVideo: [String: [Comment]] = [:]) {
        self.likedVideoList = likedVideoList
        self.savedVideoList = savedVideoList
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

    func toggleSave(videoId: String) async throws -> Bool {
        if savedVideoIDs.contains(videoId) {
            savedVideoIDs.remove(videoId)
            return false
        }
        savedVideoIDs.insert(videoId)
        return true
    }

    func savedVideos() async throws -> [SavedVideo] {
        savedVideoList
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

    func replies(forComment commentId: String, videoId: String, limit: Int) async throws -> [Comment] {
        Array((commentsByVideo[videoId] ?? []).filter { $0.parentId == commentId }.prefix(limit))
    }

    func editComment(videoId: String, commentId: String, text: String) async throws {
        guard let index = commentsByVideo[videoId]?.firstIndex(where: { $0.id == commentId }) else { return }
        commentsByVideo[videoId]?[index].text = text
        commentsByVideo[videoId]?[index].editedAt = Date()
    }

    func deleteComment(videoId: String, commentId: String) async throws {
        guard let index = commentsByVideo[videoId]?.firstIndex(where: { $0.id == commentId }) else { return }
        commentsByVideo[videoId]?[index].isDeleted = true
    }

    func toggleCommentLike(videoId: String, commentId: String) async throws -> Bool {
        guard let index = commentsByVideo[videoId]?.firstIndex(where: { $0.id == commentId }) else { return false }
        let liked = likedCommentIDs.contains(commentId)
        if liked {
            likedCommentIDs.remove(commentId)
            commentsByVideo[videoId]?[index].likeCount -= 1
        } else {
            likedCommentIDs.insert(commentId)
            commentsByVideo[videoId]?[index].likeCount += 1
        }
        return !liked
    }

    func isCommentLiked(videoId: String, commentId: String) async throws -> Bool {
        likedCommentIDs.contains(commentId)
    }

    func report(targetType: String, targetPath: String, reason: String, note: String?) async throws {}
}
