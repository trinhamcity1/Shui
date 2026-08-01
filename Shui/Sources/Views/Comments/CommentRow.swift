import SwiftUI

struct CommentRow: View {
    @Environment(\.theme) private var theme
    let comment: Comment
    let isLiked: Bool
    let canEdit: Bool
    let canDelete: Bool
    let onLike: () -> Void
    let onReply: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    @State private var isEditing = false
    @State private var editedText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(theme.surfaceSubtle)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(theme.textTertiary))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    if let handle = comment.authorHandle, !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if let createdAt = comment.createdAt {
                        Text(createdAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                if comment.isDeleted {
                    Text("Comment deleted")
                        .font(.subheadline)
                        .foregroundStyle(theme.textTertiary)
                        .italic()
                } else if isEditing {
                    editForm
                } else {
                    Text(comment.text)
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                    if comment.editedAt != nil {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                if !comment.isDeleted && !isEditing {
                    HStack(spacing: 16) {
                        Button(action: onLike) {
                            Label("\(comment.likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
                                .font(.caption)
                        }
                        .foregroundStyle(isLiked ? theme.error : theme.textSecondary)

                        Button("Reply", action: onReply)
                            .font(.caption.bold())
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            Spacer()

            if !comment.isDeleted {
                Menu {
                    if canEdit {
                        Button("Edit") {
                            editedText = comment.text
                            isEditing = true
                        }
                    }
                    if canDelete {
                        Button("Delete", role: .destructive, action: onDelete)
                    }
                    Button("Report", role: .destructive, action: onReport)
                    if !canDelete {
                        Button("Block user", role: .destructive, action: onBlock)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 32, height: 32)
                }
            }
        }
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Edit comment", text: $editedText, axis: .vertical)
                .font(.subheadline)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceSubtle))
            HStack {
                Button("Cancel") { isEditing = false }
                    .font(.caption)
                Spacer()
                Button("Save") {
                    onEdit(editedText)
                    isEditing = false
                }
                .font(.caption.bold())
                .disabled(editedText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct ReportSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, String?) -> Void

    private let reasons = ["Spam", "Harassment", "Misinformation", "Inappropriate content", "Other"]
    @State private var selectedReason: String?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason).foregroundStyle(theme.textPrimary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                }
                            }
                        }
                    }
                }
                Section("Additional details (optional)") {
                    TextField("Add context", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Report comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        guard let selectedReason else { return }
                        onSubmit(selectedReason, note.isEmpty ? nil : note)
                        dismiss()
                    }
                    .disabled(selectedReason == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
