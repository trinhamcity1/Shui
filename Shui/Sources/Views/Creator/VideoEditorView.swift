import SwiftUI

/// Per-video metadata plus the entry point into the quiz builder. Where a
/// creator lands after an upload finishes, which is why "Add quiz" is the
/// most prominent thing on it when one doesn't exist yet — a video without a
/// quiz can't be published (prompts/phase-05-creator-mode.md §4.8).
struct VideoEditorView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var video: Video
    @State private var title: String
    @State private var description: String
    @State private var transcript: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(video: Video, environment: AppEnvironment) {
        self.environment = environment
        _video = State(initialValue: video)
        _title = State(initialValue: video.title)
        _description = State(initialValue: video.description)
        _transcript = State(initialValue: video.transcript ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption).foregroundStyle(theme.textSecondary)
                    TextEditor(text: $description).frame(minHeight: 80).font(.subheadline)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $transcript).frame(minHeight: 120).font(.subheadline)
                    Text("\(transcript.count)/20000")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(transcript.count > 20000 ? theme.error : theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } header: {
                Text("Transcript")
            } footer: {
                // Stated plainly because it's the single highest-leverage
                // field on this screen: the tutor's grounding quality and
                // the quiz drafter both depend on it, and neither can say so
                // at the moment the creator skips it.
                Text("A good transcript makes the AI tutor markedly better, and is required to draft quiz questions. Leave it blank and the tutor works from the title and description only.")
            }

            Section {
                NavigationLink {
                    QuizBuilderView(video: video, environment: environment)
                } label: {
                    Label(video.hasQuiz ? "Edit quiz" : "Add quiz",
                          systemImage: video.hasQuiz ? "checklist" : "plus.circle")
                }
            } header: {
                Text("Quiz")
            } footer: {
                Text(video.hasQuiz
                     ? "This video has a quiz and can be published."
                     : "A video needs a quiz before it can be made public.")
            }

            Section("Visibility") {
                Picker("Visibility", selection: Binding(
                    get: { video.visibility },
                    set: { next in Task { await setVisibility(next) } }
                )) {
                    Text("Private").tag(Video.Visibility.private)
                    Text("Public").tag(Video.Visibility.public)
                }
                .pickerStyle(.segmented)
                statusRow
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(theme.error)
                }
            } else if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(theme.success)
                }
            }
        }
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Strings.save) { Task { await save() } }
                    .disabled(!canSave)
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Status").font(.subheadline).foregroundStyle(theme.textSecondary)
            Spacer()
            switch video.status {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(theme.success)
            case .pending, .uploading:
                Label("Processing", systemImage: "clock").font(.caption).foregroundStyle(theme.info)
            case .failed:
                Label(video.statusMessage ?? "Upload failed", systemImage: "xmark.circle.fill")
                    .font(.caption).foregroundStyle(theme.error)
            }
        }
    }

    private func save() async {
        guard let videoId = video.id else { return }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            try await environment.videos.updateMetadata(
                videoId: videoId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                // Send nil rather than "" so clearing the box doesn't write
                // an empty string the tutor would then treat as a transcript
                // that exists but says nothing.
                transcript: transcript.isEmpty ? nil : transcript
            )
            video.title = title
            video.description = description
            video.transcript = transcript.isEmpty ? nil : transcript
            successMessage = "Saved."
        } catch {
            errorMessage = "Couldn't save. Check your connection and try again."
        }
    }

    private func setVisibility(_ next: Video.Visibility) async {
        guard let videoId = video.id else { return }
        errorMessage = nil
        do {
            try await environment.videos.setVisibility(videoId: videoId, visibility: next)
            video.visibility = next
        } catch {
            // "Add a quiz before publishing this video." is the Function's
            // own wording and is more useful than anything generic.
            errorMessage = error.localizedDescription
        }
    }
}
