import SwiftUI

/// The "Info" panel for a feed lesson: the in-depth civics explanation for
/// every question the lesson covers, followed by the community comments
/// thread. Comments are stored locally in SwiftData (mirroring the spec's
/// Comments table shape) — swapping in a remote service later changes the
/// storage, not this view. All of this is available to free users.
struct LessonInfoSheet: View {
    let lesson: LessonScript

    @EnvironmentObject private var appState: AppState
    @State private var comments: [LessonComment] = []
    @State private var draftText = ""
    @State private var replyTarget: LessonComment?

    private var language: AppLanguage { appState.profile.uiLanguage }
    private var coveredQuestions: [CivicsQuestion] {
        lesson.questionIds.compactMap { ContentStore.shared.question(id: $0) }
    }
    private var topLevelComments: [LessonComment] {
        comments.filter { $0.parentID == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    explanationSection
                    Divider()
                    commentsSection
                }
                .padding()
            }
            .background(Theme.shell.canvas)
            .navigationTitle(language == .vietnamese ? lesson.titleVI : lesson.titleEN)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
            .onAppear { reloadComments() }
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.infoExplanationTitle.localized)
                .font(.headline)
                .foregroundStyle(Theme.shell.ink)
            ForEach(coveredQuestions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.questionEN)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.shell.ink)
                    Text(question.explanationVI)
                        .font(.subheadline)
                        .foregroundStyle(Theme.shell.ink.opacity(0.85))
                    Text(question.quickFactEN)
                        .font(.caption)
                        .foregroundStyle(Theme.shell.metadata)
                }
                .shuiCard()
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.commentsTitle.localized)
                .font(.headline)
                .foregroundStyle(Theme.shell.ink)

            if topLevelComments.isEmpty {
                Text(L10n.commentsEmpty.localized)
                    .font(.subheadline)
                    .foregroundStyle(Theme.shell.metadata)
            } else {
                ForEach(topLevelComments, id: \.id) { comment in
                    commentRow(comment, isReply: false)
                    ForEach(replies(to: comment), id: \.id) { reply in
                        commentRow(reply, isReply: true)
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: LessonComment, isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.authorName)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.shell.ink)
                Text(comment.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.shell.metadata)
            }
            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.ink)
            if !isReply {
                Button(L10n.commentsReply.localized) {
                    replyTarget = comment
                }
                .font(.caption)
                .tint(Theme.shell.gradientEnd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shuiCard()
        .padding(.leading, isReply ? 28 : 0)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let replyTarget {
                HStack {
                    Text("\(L10n.commentsReply.localized): \(replyTarget.authorName)")
                        .font(.caption)
                        .foregroundStyle(Theme.shell.metadata)
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.shell.metadata)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(L10n.commentsPlaceholder.localized, text: $draftText)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.commentsSend.localized, action: submitComment)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.shell.gradientStart)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func replies(to comment: LessonComment) -> [LessonComment] {
        comments.filter { $0.parentID == comment.id }
    }

    private func submitComment() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let author = appState.profile.displayName.isEmpty
            ? L10n.commentsGuestName.localized
            : appState.profile.displayName
        PersistenceController.shared.addComment(
            lessonID: lesson.id,
            authorName: author,
            text: text,
            parentID: replyTarget?.id
        )
        draftText = ""
        replyTarget = nil
        reloadComments()
    }

    private func reloadComments() {
        comments = PersistenceController.shared.comments(for: lesson.id)
    }
}
