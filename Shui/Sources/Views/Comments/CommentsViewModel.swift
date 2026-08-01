import Foundation

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var repliesByParent: [String: [Comment]] = [:]
    @Published private(set) var expandedParents: Set<String> = []
    @Published private(set) var likedCommentIDs: Set<String> = []
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published var loadError: String?
    @Published var draftText = ""
    @Published var replyTarget: Comment?
    @Published private(set) var isSubmitting = false
    @Published private(set) var submissionFailedDraft: String?
    /// Bumped after a block, since `visibleComments`/`repliesPreview` filter
    /// against `BlockedUsersStore` (not a `@Published` property this object
    /// owns) — mutating this is what tells SwiftUI to re-read them.
    @Published private(set) var blockListVersion = 0
    /// Starts from the video's denormalized `commentCount` and adjusts as
    /// top-level comments are actually posted this session — not re-derived
    /// from a separate query.
    @Published private(set) var totalCount: Int

    let videoId: String
    private let environment: AppEnvironment
    private var cursor: PageCursor?
    private var hasMore = true
    private let pageSize = 20

    var isGuest: Bool { environment.isGuest }

    var visibleComments: [Comment] {
        _ = blockListVersion
        let blocked = BlockedUsersStore.blockedIDs()
        return comments.filter { !blocked.contains($0.uid) }
    }

    init(videoId: String, initialCount: Int, environment: AppEnvironment) {
        self.videoId = videoId
        self.totalCount = initialCount
        self.environment = environment
    }

    // MARK: - Loading

    func loadInitial() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        comments = []
        cursor = nil
        hasMore = true
        await loadMore()
    }

    func loadMoreIfNeeded(currentlyShowing comment: Comment) {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }), comments.count - index <= 5 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await environment.social.comments(forVideo: videoId, limit: pageSize, after: cursor)
            comments.append(contentsOf: page.items)
            cursor = page.cursor
            hasMore = page.items.count == pageSize
        } catch {
            loadError = error.localizedDescription
        }
    }

    func loadReplies(for comment: Comment) async {
        guard let id = comment.id, repliesByParent[id] == nil else { return }
        repliesByParent[id] = (try? await environment.social.replies(forComment: id, videoId: videoId, limit: 50)) ?? []
    }

    func repliesPreview(for comment: Comment) -> [Comment] {
        guard let id = comment.id else { return [] }
        let blocked = BlockedUsersStore.blockedIDs()
        let all = (repliesByParent[id] ?? []).filter { !blocked.contains($0.uid) }
        return expandedParents.contains(id) ? all : Array(all.prefix(3))
    }

    func remainingReplyCount(for comment: Comment) -> Int? {
        guard let id = comment.id, !expandedParents.contains(id) else { return nil }
        let blocked = BlockedUsersStore.blockedIDs()
        let remaining = (repliesByParent[id] ?? []).filter { !blocked.contains($0.uid) }.count - 3
        return remaining > 0 ? remaining : nil
    }

    func expand(_ comment: Comment) {
        guard let id = comment.id else { return }
        expandedParents.insert(id)
    }

    func refreshVisibility() {
        blockListVersion += 1
    }

    // MARK: - Posting

    /// A locally-built placeholder is inserted immediately (optimistic),
    /// then either replaced with the server-confirmed list (success) or
    /// removed with the draft restored for retry (failure) — never left
    /// showing a comment the server never actually accepted.
    func post() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let parentId = replyTarget?.id
        let clearedTarget = replyTarget
        let tempID = "pending-\(UUID().uuidString)"
        let account = environment.currentUser
        let optimistic = Comment(
            id: tempID,
            uid: account?.id ?? "",
            authorName: account?.displayName ?? "Learner",
            authorPhotoURL: account?.photoURL,
            authorHandle: (account?.handle.isEmpty ?? true) ? nil : account?.handle,
            text: text,
            createdAt: Date(),
            editedAt: nil,
            parentId: parentId,
            replyCount: 0,
            likeCount: 0,
            isDeleted: false,
            reportCount: 0
        )

        isSubmitting = true
        submissionFailedDraft = nil
        draftText = ""
        replyTarget = nil
        if let parentId {
            repliesByParent[parentId, default: []].append(optimistic)
            expandedParents.insert(parentId)
        } else {
            comments.insert(optimistic, at: 0)
        }

        do {
            try await environment.social.postComment(videoId: videoId, text: text, parentId: parentId)
            AppAnalytics.logCommentPosted(videoId: videoId, isReply: parentId != nil)
            totalCount += 1 // matches onCommentWritten: every non-deleted comment counts, reply or not
            if let parentId {
                repliesByParent[parentId] = try await environment.social.replies(forComment: parentId, videoId: videoId, limit: 50)
            } else {
                await loadInitial()
            }
        } catch {
            if let parentId {
                repliesByParent[parentId]?.removeAll { $0.id == tempID }
            } else {
                comments.removeAll { $0.id == tempID }
            }
            draftText = text
            replyTarget = clearedTarget
            submissionFailedDraft = text
        }
        isSubmitting = false
    }

    func retry() async {
        guard let draft = submissionFailedDraft else { return }
        draftText = draft
        submissionFailedDraft = nil
        await post()
    }

    // MARK: - Edit / delete / report

    func canEdit(_ comment: Comment) -> Bool {
        guard comment.uid == environment.currentUser?.id, let createdAt = comment.createdAt else { return false }
        return Date().timeIntervalSince(createdAt) < 15 * 60
    }

    func canDelete(_ comment: Comment) -> Bool {
        comment.uid == environment.currentUser?.id || environment.currentUser?.role == .admin
    }

    func edit(_ comment: Comment, text: String) async {
        guard let commentId = comment.id else { return }
        try? await environment.social.editComment(videoId: videoId, commentId: commentId, text: text)
        mutate(commentId: commentId) { $0.text = text; $0.editedAt = Date() }
    }

    func delete(_ comment: Comment) async {
        guard let commentId = comment.id else { return }
        try? await environment.social.deleteComment(videoId: videoId, commentId: commentId)
        mutate(commentId: commentId) { $0.isDeleted = true }
    }

    func report(_ comment: Comment, reason: String, note: String?) async {
        guard let commentId = comment.id else { return }
        try? await environment.social.report(
            targetType: "comment",
            targetPath: "videos/\(videoId)/comments/\(commentId)",
            reason: reason,
            note: note
        )
    }

    // MARK: - Likes

    func toggleLike(_ comment: Comment) async {
        guard let commentId = comment.id else { return }
        let wasLiked = likedCommentIDs.contains(commentId)
        applyLikeState(commentId: commentId, liked: !wasLiked)
        do {
            _ = try await environment.social.toggleCommentLike(videoId: videoId, commentId: commentId)
        } catch {
            applyLikeState(commentId: commentId, liked: wasLiked)
        }
    }

    private func applyLikeState(commentId: String, liked: Bool) {
        let alreadyLiked = likedCommentIDs.contains(commentId)
        guard alreadyLiked != liked else { return }
        if liked {
            likedCommentIDs.insert(commentId)
        } else {
            likedCommentIDs.remove(commentId)
        }
        mutate(commentId: commentId) { $0.likeCount += liked ? 1 : -1 }
    }

    // MARK: - Shared mutation helper

    private func mutate(commentId: String, _ apply: (inout Comment) -> Void) {
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            apply(&comments[index])
            return
        }
        for (parentId, replies) in repliesByParent {
            if let index = replies.firstIndex(where: { $0.id == commentId }) {
                var updated = replies
                apply(&updated[index])
                repliesByParent[parentId] = updated
                return
            }
        }
    }
}
