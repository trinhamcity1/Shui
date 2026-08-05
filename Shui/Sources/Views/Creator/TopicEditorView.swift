import PhotosUI
import SwiftUI

/// Create and edit in one form (prompts/phase-05-creator-mode.md §3), with
/// the topic's ordered video list below it. Handles both "brand new draft"
/// and "existing topic" — the only difference is whether Save creates or
/// updates, and whether the video list has anything to show yet.
struct TopicEditorView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TopicEditorViewModel

    @State private var tagDraft = ""
    @State private var showPreview = false
    @State private var coverItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmText = ""
    @State private var showUpload = false
    @State private var videoPendingDelete: Video?

    init(topicId: String?, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: TopicEditorViewModel(topicId: topicId, draftTopic: nil, environment: environment))
    }

    init(draftTopic: Topic, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: TopicEditorViewModel(topicId: nil, draftTopic: draftTopic, environment: environment))
    }

    var body: some View {
        Form {
            if let draft = viewModel.recoverableDraft {
                Section {
                    Label("Unsaved changes from \(draft.savedAt.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(theme.warning)
                    Button("Restore them") { viewModel.restoreDraft() }
                    Button("Discard", role: .destructive) { viewModel.discardDraft() }
                } footer: {
                    Text("Kept on this device when a save didn't go through.")
                }
            }
            detailsSection
            coverSection
            tagsSection
            if !viewModel.isNew {
                videosSection
                publishSection
                dangerSection
            } else {
                Section {
                    Text("Save this topic to start adding videos.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            messageSection
        }
        .navigationTitle(viewModel.isNew ? "New topic" : "Edit topic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Strings.save) {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.canSave)
            }
            if viewModel.isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            } else if viewModel.videos.count > 1 {
                // `.onMove` only exposes drag handles in edit mode — without
                // this the reorder affordance exists but is unreachable.
                // Trailing, not leading: this screen is pushed, and a
                // leading item would sit against the back button.
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .task { await viewModel.load() }
        // Mirror the long-form fields locally on every edit — §7's "losing a
        // quiz you typed on the subway is unacceptable" applies just as much
        // to a topic description.
        .onChange(of: viewModel.title) { _, _ in viewModel.persistDraftLocally() }
        .onChange(of: viewModel.subtitle) { _, _ in viewModel.persistDraftLocally() }
        .onChange(of: viewModel.description) { _, _ in viewModel.persistDraftLocally() }
        .onChange(of: viewModel.tags) { _, _ in viewModel.persistDraftLocally() }
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await viewModel.uploadCover(data)
            }
        }
        .sheet(isPresented: $showUpload, onDismiss: { Task { await viewModel.reloadVideos() } }) {
            if let topic = currentTopic {
                VideoUploadFlowView(topic: topic, environment: environment)
            }
        }
        .confirmationDialog(
            "Remove this video?",
            isPresented: Binding(get: { videoPendingDelete != nil }, set: { if !$0 { videoPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let video = videoPendingDelete {
                    Task { await viewModel.deleteVideo(video) }
                }
                videoPendingDelete = nil
            }
            Button(Strings.cancel, role: .cancel) { videoPendingDelete = nil }
        } message: {
            Text("Learners will stop seeing it. This can be undone by support, but not from the app.")
        }
        .alert("Delete this topic?", isPresented: $showDeleteConfirm) {
            TextField("Type the topic title", text: $deleteConfirmText)
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.softDeleteTopic() { dismiss() }
                }
            }
            .disabled(deleteConfirmText != viewModel.title)
            Button(Strings.cancel, role: .cancel) { deleteConfirmText = "" }
        } message: {
            Text("This hides every video inside it. Type the topic's title to confirm.")
        }
    }

    private var currentTopic: Topic? {
        guard let id = viewModel.topicId else { return nil }
        var topic = Topic.newDraft(createdBy: environment.auth.currentUID ?? "", createdByName: "")
        topic.id = id
        topic.title = viewModel.title
        topic.categoryId = viewModel.categoryId
        return topic
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Details") {
            LabeledField(label: "Title", error: viewModel.fieldErrors.title) {
                TextField("What is this topic called?", text: $viewModel.title)
            }
            LabeledField(label: "Subtitle", error: viewModel.fieldErrors.subtitle) {
                TextField("One line describing it", text: $viewModel.subtitle)
            }
            Picker("Category", selection: $viewModel.categoryId) {
                Text("Choose…").tag("")
                ForEach(viewModel.categories) { category in
                    Text(category.title).tag(category.id ?? "")
                }
            }
            if let error = viewModel.fieldErrors.category {
                Text(error).font(.caption).foregroundStyle(theme.error)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description").font(.subheadline).foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button(showPreview ? "Edit" : "Preview") { showPreview.toggle() }
                        .font(.caption)
                }
                if showPreview {
                    // Markdown is rendered with SwiftUI's own parser rather
                    // than a dependency — it covers the inline subset
                    // (bold/italic/links/code) that a topic description
                    // realistically uses, and failing to parse degrades to
                    // showing the raw text rather than an error.
                    Text(LocalizedStringKey(viewModel.description))
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    TextEditor(text: $viewModel.description)
                        .frame(minHeight: 120)
                        .font(.subheadline)
                }
                HStack {
                    if let error = viewModel.fieldErrors.description {
                        Text(error).font(.caption).foregroundStyle(theme.error)
                    }
                    Spacer()
                    Text("\(viewModel.description.count)/4000")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(viewModel.description.count > 4000 ? theme.error : theme.textTertiary)
                }
            }
        }
    }

    private var coverSection: some View {
        Section("Cover image") {
            if let urlString = viewModel.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(3 / 2, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.surfaceSubtle)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .listRowInsets(EdgeInsets())
            }
            PhotosPicker(selection: $coverItem, matching: .images) {
                Label(viewModel.coverImageURL == nil ? "Choose cover image" : "Replace cover image",
                      systemImage: "photo")
            }
            .disabled(viewModel.isNew)
            if viewModel.isNew {
                Text("Available once the topic is saved.")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var tagsSection: some View {
        Section {
            if !viewModel.tags.isEmpty {
                // A wrapping flow of chips rather than a horizontal scroll —
                // 8 short tags fit in two or three lines, and hiding some
                // off-screen makes it easy to forget one is there.
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        Button {
                            viewModel.removeTag(tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.shuiPillOutline)
                    }
                }
            }
            HStack {
                TextField("Add a tag", text: $tagDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { commitTag() }
                Button("Add") { commitTag() }
                    .font(.caption)
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.tags.count >= 8)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Up to 8, lowercase. Tags help learners find this topic in search.")
        }
    }

    private var videosSection: some View {
        Section {
            if viewModel.videos.isEmpty {
                Text("No videos yet.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(viewModel.videos) { video in
                    NavigationLink {
                        VideoEditorView(video: video, environment: environment)
                    } label: {
                        CreatorVideoRow(video: video)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            videoPendingDelete = video
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            Task {
                                await viewModel.setVideoVisibility(video, to: video.visibility == .public ? .private : .public)
                            }
                        } label: {
                            Label(video.visibility == .public ? "Make private" : "Make public",
                                  systemImage: video.visibility == .public ? "eye.slash" : "eye")
                        }
                        .tint(theme.accent)
                    }
                }
                .onMove { source, destination in
                    Task { await viewModel.reorder(from: source, to: destination) }
                }
            }
            Button {
                showUpload = true
            } label: {
                Label("Upload video", systemImage: "arrow.up.circle")
            }
        } header: {
            HStack {
                Text("Videos")
                Spacer()
                if viewModel.videos.count > 1 {
                    Text("Drag to reorder").font(.caption2).foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private var publishSection: some View {
        Section {
            ForEach(viewModel.publishChecklist, id: \.text) { item in
                Label(item.text, systemImage: item.satisfied ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(item.satisfied ? theme.success : theme.textSecondary)
            }
            if viewModel.visibility == .public {
                Button("Unpublish") {
                    Task { await viewModel.setVisibility(.private) }
                }
            } else {
                Button("Publish") {
                    Task { await viewModel.setVisibility(.public) }
                }
                .disabled(!viewModel.canPublish)
            }
        } header: {
            Text(viewModel.visibility == .public ? "Published" : "Publishing")
        } footer: {
            Text(viewModel.visibility == .public
                 ? "Learners can find this topic in Explore and its videos in the feed."
                 : "Only the first item is required to publish. The rest make the topic better.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Duplicate structure") {
                Task { await viewModel.duplicateTopic() }
            }
            Button("Delete topic", role: .destructive) {
                deleteConfirmText = ""
                showDeleteConfirm = true
            }
        } footer: {
            Text("Duplicating copies the details and tags, not the videos.")
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = viewModel.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.error)
            }
        } else if let success = viewModel.successMessage {
            Section {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.success)
            }
        }
    }

    private func commitTag() {
        viewModel.addTag(tagDraft)
        tagDraft = ""
    }
}

/// Label + field + inline error, so every form row reports its own problem
/// next to the thing that's wrong rather than in a summary at the bottom.
private struct LabeledField<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    let error: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            content
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.error)
            }
        }
    }
}

private struct CreatorVideoRow: View {
    @Environment(\.theme) private var theme
    let video: Video

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.surfaceSubtle)
                if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "video")
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(width: 40, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title.isEmpty ? "Untitled" : video.title)
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                StatusBadge(video: video)
            }
        }
    }
}

/// One badge with the single most important thing about this row's state —
/// a row that is both "processing" and "needs quiz" is really just
/// "processing" until that finishes.
private struct StatusBadge: View {
    @Environment(\.theme) private var theme
    let video: Video

    var body: some View {
        let (text, color) = state
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }

    private var state: (String, Color) {
        switch video.status {
        case .pending, .uploading:
            return ("Uploading", theme.info)
        case .failed:
            return ("Upload failed", theme.error)
        case .ready:
            if !video.hasQuiz { return ("Needs quiz", theme.warning) }
            return video.visibility == .public ? ("Ready", theme.success) : ("Private", theme.textTertiary)
        }
    }
}
