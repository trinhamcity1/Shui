import SwiftUI

/// Creator mode's landing screen — a dashboard, not a menu
/// (prompts/phase-05-creator-mode.md §2). Leads with what needs work rather
/// than a list of links, because the whole point of this phase is that
/// content stops being a build artifact and starts being something you
/// maintain from a phone.
///
/// Reached from Settings → Creator, pushed onto that sheet's existing
/// `NavigationStack` — deliberately not a fourth tab: this is a mode, not a
/// peer of Learn.
struct CreatorHomeView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: CreatorHomeViewModel
    @State private var newTopic: Topic?
    @State private var uploadDestination: CreatorTopicSummary?

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: CreatorHomeViewModel(environment: environment))
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(theme.error)
                }
            }

            if viewModel.isEmpty {
                Section { emptyState }
            }

            if !viewModel.drafts.isEmpty {
                Section {
                    ForEach(viewModel.drafts) { summary in
                        NavigationLink {
                            TopicEditorView(topicId: summary.topic.id, environment: environment)
                        } label: {
                            CreatorTopicRow(summary: summary, isDraft: true)
                        }
                    }
                } header: {
                    Text("Drafts and private")
                } footer: {
                    Text("Only you can see these. Publishing needs at least one video that finished uploading.")
                }
            }

            if !viewModel.published.isEmpty {
                Section("Published") {
                    ForEach(viewModel.published) { summary in
                        NavigationLink {
                            TopicEditorView(topicId: summary.topic.id, environment: environment)
                        } label: {
                            CreatorTopicRow(summary: summary, isDraft: false)
                        }
                    }
                }
            }

            if environment.isAdmin {
                Section {
                    NavigationLink {
                        AdminHomeView(environment: environment)
                    } label: {
                        Label("Admin", systemImage: "shield.lefthalf.filled")
                    }
                }
            }
        }
        .navigationTitle("Creator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newTopic = Topic.newDraft(createdBy: environment.auth.currentUID ?? "",
                                                  createdByName: environment.currentUser?.displayName ?? "")
                    } label: {
                        Label("New topic", systemImage: "folder.badge.plus")
                    }
                    // Upload needs a destination topic, so it's only offered
                    // once one exists — otherwise the flow would dead-end on
                    // a picker with nothing in it.
                    Button {
                        uploadDestination = viewModel.drafts.first ?? viewModel.published.first
                    } label: {
                        Label("Upload video", systemImage: "arrow.up.circle")
                    }
                    .disabled(viewModel.drafts.isEmpty && viewModel.published.isEmpty)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .sheet(item: $newTopic, onDismiss: { Task { await viewModel.load() } }) { draft in
            NavigationStack {
                TopicEditorView(draftTopic: draft, environment: environment)
            }
        }
        .sheet(item: $uploadDestination, onDismiss: { Task { await viewModel.load() } }) { summary in
            VideoUploadFlowView(topic: summary.topic, environment: environment)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(theme.textTertiary)
            Text("No topics yet")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text("A topic is an ordered set of short videos. Create one, upload a video, write its quiz, then publish.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("New topic") {
                newTopic = Topic.newDraft(createdBy: environment.auth.currentUID ?? "",
                                          createdByName: environment.currentUser?.displayName ?? "")
            }
            .buttonStyle(.shuiPill)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct CreatorTopicRow: View {
    @Environment(\.theme) private var theme
    let summary: CreatorTopicSummary
    let isDraft: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            if isDraft {
                if summary.blockers.isEmpty {
                    Label("Ready to publish", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(theme.success)
                } else {
                    // Every blocker, not just the first — "2 videos have no
                    // quiz" and "no cover image" are different jobs, and
                    // showing one at a time turns fixing a topic into a
                    // guessing game.
                    ForEach(summary.blockers, id: \.self) { blocker in
                        Label(blocker, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(theme.warning)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    stat("\(summary.topic.learnerCount)", label: "learners")
                    stat("\(summary.totalViews)", label: "views")
                    stat("\(summary.readyVideos.count)", label: "videos")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stat(_ value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

extension Topic {
    /// A blank topic the editor can bind to before anything is saved. Starts
    /// private with zeroed counters to match exactly what rules allow a
    /// creator to write on create — the server ignores these values anyway,
    /// but starting them anywhere else would make the form lie about what's
    /// about to happen.
    static func newDraft(createdBy: String, createdByName: String) -> Topic {
        Topic(
            id: nil,
            title: "",
            subtitle: "",
            description: "",
            categoryId: "",
            coverImageURL: nil,
            visibility: .private,
            createdBy: createdBy,
            createdByName: createdByName,
            createdAt: nil,
            updatedAt: nil,
            publishedAt: nil,
            videoCount: 0,
            totalDurationSec: 0,
            learnerCount: 0,
            tags: [],
            isDeleted: false
        )
    }
}
