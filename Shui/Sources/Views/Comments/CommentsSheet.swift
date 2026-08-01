import SwiftUI

/// Presented from the feed's comment button, over the paused video. One
/// level of threading (top-level comments, each with up to 3 visible
/// replies and a "View N replies" expander), a composer pinned to the
/// bottom that's replaced by a sign-in prompt for guests, and optimistic
/// posting reconciled against the server write.
struct CommentsSheet: View {
    let videoId: String
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CommentsViewModel
    @State private var showSignInSheet = false
    @State private var reportTarget: Comment?
    @State private var blockCandidate: Comment?
    @FocusState private var composerFocused: Bool

    /// `initialCommentCount` is the video's own denormalized `commentCount`
    /// (already on screen via the feed's right rail) — the header's "· N"
    /// starts from that rather than a separate count query, and adjusts as
    /// comments are actually posted in this session.
    init(videoId: String, initialCommentCount: Int, environment: AppEnvironment) {
        self.videoId = videoId
        self.environment = environment
        _viewModel = StateObject(
            wrappedValue: CommentsViewModel(videoId: videoId, initialCount: initialCommentCount, environment: environment)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                list
                Divider()
                composer
            }
            .navigationTitle("Comments · \(viewModel.totalCount)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await viewModel.loadInitial() }
        .sheet(isPresented: $showSignInSheet) { SignInSheet() }
        .sheet(item: $reportTarget) { comment in
            ReportSheet(onSubmit: { reason, note in
                Task { await viewModel.report(comment, reason: reason, note: note) }
            })
        }
        .confirmationDialog(
            "Block this user?", isPresented: Binding(get: { blockCandidate != nil }, set: { if !$0 { blockCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                if let uid = blockCandidate?.uid {
                    BlockedUsersStore.block(uid)
                    viewModel.refreshVisibility()
                }
                blockCandidate = nil
            }
        } message: {
            Text("You won't see comments from this person again on this device.")
        }
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = viewModel.loadError, viewModel.comments.isEmpty {
            FeedErrorStateView(message: loadError, onRetry: { Task { await viewModel.loadInitial() } })
        } else if viewModel.visibleComments.isEmpty {
            VStack(spacing: 8) {
                Text("No comments yet")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("Be the first to say something.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.visibleComments) { comment in
                        CommentThread(
                            comment: comment,
                            viewModel: viewModel,
                            onReply: {
                                viewModel.replyTarget = comment
                                composerFocused = true
                            },
                            onReport: { reportTarget = comment },
                            onBlock: { blockCandidate = comment },
                            requireSignIn: { showSignInSheet = true }
                        )
                        .onAppear {
                            Task { await viewModel.loadReplies(for: comment) }
                            viewModel.loadMoreIfNeeded(currentlyShowing: comment)
                        }
                        Divider().padding(.leading, 56)
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        if environment.isGuest {
            Button("Sign in to join the conversation") { showSignInSheet = true }
                .buttonStyle(.shuiPill)
                .padding(16)
        } else {
            VStack(spacing: 8) {
                if let target = viewModel.replyTarget {
                    HStack(spacing: 6) {
                        Text("Replying to \(target.authorName)")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button {
                            viewModel.replyTarget = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if let failedDraft = viewModel.submissionFailedDraft {
                    HStack {
                        Text("Couldn't post: \(failedDraft)")
                            .font(.caption)
                            .foregroundStyle(theme.error)
                            .lineLimit(1)
                        Spacer()
                        Button("Retry") { Task { await viewModel.retry() } }
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 16)
                }
                HStack(spacing: 10) {
                    TextField("Add a comment", text: $viewModel.draftText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceSubtle))
                    Button {
                        Task { await viewModel.post() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(viewModel.draftText.trimmingCharacters(in: .whitespaces).isEmpty ? theme.textTertiary : theme.accent)
                    }
                    .disabled(viewModel.draftText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSubmitting)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
    }
}

private struct CommentThread: View {
    @ObservedObject var viewModel: CommentsViewModel
    let comment: Comment
    let onReply: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let requireSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(
                comment: comment,
                isLiked: viewModel.likedCommentIDs.contains(comment.id ?? ""),
                canEdit: viewModel.canEdit(comment),
                canDelete: viewModel.canDelete(comment),
                onLike: {
                    guard !viewModel.isGuest else { requireSignIn(); return }
                    Task { await viewModel.toggleLike(comment) }
                },
                onReply: {
                    guard !viewModel.isGuest else { requireSignIn(); return }
                    onReply()
                },
                onEdit: { newText in Task { await viewModel.edit(comment, text: newText) } },
                onDelete: { Task { await viewModel.delete(comment) } },
                onReport: onReport,
                onBlock: onBlock
            )

            let replies = viewModel.repliesPreview(for: comment)
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(replies) { reply in
                        CommentRow(
                            comment: reply,
                            isLiked: viewModel.likedCommentIDs.contains(reply.id ?? ""),
                            canEdit: viewModel.canEdit(reply),
                            canDelete: viewModel.canDelete(reply),
                            onLike: {
                                guard !viewModel.isGuest else { requireSignIn(); return }
                                Task { await viewModel.toggleLike(reply) }
                            },
                            onReply: {
                                guard !viewModel.isGuest else { requireSignIn(); return }
                                onReply()
                            },
                            onEdit: { newText in Task { await viewModel.edit(reply, text: newText) } },
                            onDelete: { Task { await viewModel.delete(reply) } },
                            onReport: onReport,
                            onBlock: onBlock
                        )
                    }
                    if let more = viewModel.remainingReplyCount(for: comment), more > 0 {
                        Button("View \(more) more repl\(more == 1 ? "y" : "ies")") {
                            viewModel.expand(comment)
                        }
                        .font(.caption.bold())
                        .padding(.leading, 44)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
