import SwiftUI

/// Per-video quiz authoring (prompts/phase-05-creator-mode.md §5). Every
/// validation rule here mirrors `saveQuiz`'s server-side schema, shown
/// inline as you type, so a save never fails for something the form could
/// have told you about first.
struct QuizBuilderView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: QuizBuilderViewModel
    @State private var showPreview = false

    init(video: Video, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: QuizBuilderViewModel(video: video, environment: environment))
    }

    var body: some View {
        Form {
            if viewModel.isLoading {
                Section { ProgressView() }
            }

            if let draft = viewModel.recoverableDraft {
                Section {
                    Label("You have unsaved changes from \(draft.savedAt.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(theme.warning)
                    Button("Restore them") { viewModel.restoreDraft() }
                    Button("Discard", role: .destructive) { viewModel.discardDraft() }
                } footer: {
                    Text("Saved on this device when a save didn't go through. The version on the server is shown until you restore.")
                }
            }

            draftSection

            ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                questionSection(index: index, question: question)
            }

            Section {
                Button {
                    viewModel.addQuestion()
                } label: {
                    Label("Add question", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canAddQuestion)
            } footer: {
                Text("A quiz holds 1–5 questions. \(viewModel.questions.count) so far.")
            }

            passThresholdSection

            if !viewModel.quizErrors.isEmpty {
                Section {
                    ForEach(viewModel.quizErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(theme.error)
                    }
                }
            }

            messageSection
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Strings.save) {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
            // Trailing alongside Save rather than leading: these screens are
            // pushed, and a leading item sits next to the back button.
            ToolbarItem(placement: .primaryAction) {
                Button("Preview") { showPreview = true }
                    .disabled(viewModel.questions.isEmpty)
            }
        }
        .task { await viewModel.load() }
        // Mirrors every edit to local storage so a lost connection, a crash,
        // or a backgrounded app doesn't take a half-written quiz with it.
        .onChange(of: viewModel.questions) { _, _ in viewModel.persistDraftLocally() }
        .onChange(of: viewModel.passThreshold) { _, _ in viewModel.persistDraftLocally() }
        .sheet(isPresented: $showPreview) {
            QuizPreviewSheet(video: viewModel.video, quiz: viewModel.previewQuiz)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var draftSection: some View {
        Section {
            Button {
                Task { await viewModel.draftWithAI() }
            } label: {
                HStack {
                    Label("Suggest questions", systemImage: "sparkles")
                    if viewModel.isDrafting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isDrafting || !viewModel.canAddQuestion || !viewModel.hasTranscript)
        } header: {
            Text("Draft with AI")
        } footer: {
            // States the constraint rather than silently disabling the
            // button — the server refuses to draft without a transcript
            // because a quiz invented from a title alone is the easiest
            // kind of wrong quiz to ship.
            if viewModel.hasTranscript {
                Text("Drafts are starting points, never saved for you. Review and edit every question before saving.")
            } else {
                Text("Add a transcript to this video first — questions drafted without one would be guesses, not comprehension checks.")
            }
        }
    }

    private func questionSection(index: Int, question: QuizQuestionDraft) -> some View {
        Section {
            TextField("Question", text: binding(for: index).prompt, axis: .vertical)
                .lineLimit(1...4)

            ForEach(question.options) { option in
                HStack(spacing: 10) {
                    Button {
                        viewModel.toggleCorrect(option.id, forQuestionAt: index)
                    } label: {
                        Image(systemName: question.correctOptionIds.contains(option.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(question.correctOptionIds.contains(option.id)
                                             ? theme.success : theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(question.correctOptionIds.contains(option.id)
                                        ? "Correct answer" : "Mark as correct")

                    TextField("Option", text: optionBinding(questionIndex: index, optionId: option.id))

                    if question.options.count > 2 {
                        Button {
                            viewModel.removeOption(option.id, fromQuestionAt: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if question.options.count < 6 {
                Button {
                    viewModel.addOption(toQuestionAt: index)
                } label: {
                    Label("Add option", systemImage: "plus")
                        .font(.caption)
                }
            }

            if question.correctOptionIds.count > 1 {
                Stepper(
                    "Must get \(question.requiredCorrectCount) of \(question.correctOptionIds.count) right",
                    value: binding(for: index).requiredCorrectCount,
                    in: 1...max(1, question.correctOptionIds.count)
                )
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Explanation").font(.caption).foregroundStyle(theme.textSecondary)
                TextEditor(text: binding(for: index).explanation)
                    .frame(minHeight: 70)
                    .font(.subheadline)
            }

            ForEach(QuizValidation.errors(for: question), id: \.self) { error in
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(theme.error)
            }

            Button("Remove question", role: .destructive) {
                viewModel.removeQuestion(at: index)
            }
            .font(.caption)
        } header: {
            Text("Question \(index + 1)")
        }
    }

    private var passThresholdSection: some View {
        Section {
            Slider(value: $viewModel.passThreshold, in: 0.2...1.0, step: 0.1)
            Text("Pass at \(Int(viewModel.passThreshold * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
        } header: {
            Text("Passing score")
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

    // MARK: - Bindings

    /// Index-based bindings into the published array. Guarded on every access
    /// because a question can be removed while its row is still on screen
    /// mid-render, and an unguarded subscript would trap.
    private func binding(for index: Int) -> Binding<QuizQuestionDraft> {
        Binding(
            get: {
                viewModel.questions.indices.contains(index)
                    ? viewModel.questions[index]
                    : QuizQuestionDraft(id: "", prompt: "", options: [], correctOptionIds: [],
                                        requiredCorrectCount: 1, explanation: "", orderIndex: 0)
            },
            set: { newValue in
                guard viewModel.questions.indices.contains(index) else { return }
                viewModel.questions[index] = newValue
            }
        )
    }

    private func optionBinding(questionIndex: Int, optionId: String) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.questions.indices.contains(questionIndex),
                      let option = viewModel.questions[questionIndex].options.first(where: { $0.id == optionId })
                else { return "" }
                return option.text
            },
            set: { newValue in
                guard viewModel.questions.indices.contains(questionIndex),
                      let optionIndex = viewModel.questions[questionIndex].options
                        .firstIndex(where: { $0.id == optionId })
                else { return }
                viewModel.questions[questionIndex].options[optionIndex].text = newValue
            }
        )
    }
}

private extension Binding where Value == QuizQuestionDraft {
    var prompt: Binding<String> {
        Binding<String>(get: { wrappedValue.prompt }, set: { wrappedValue.prompt = $0 })
    }
    var explanation: Binding<String> {
        Binding<String>(get: { wrappedValue.explanation }, set: { wrappedValue.explanation = $0 })
    }
    var requiredCorrectCount: Binding<Int> {
        Binding<Int>(get: { wrappedValue.requiredCorrectCount }, set: { wrappedValue.requiredCorrectCount = $0 })
    }
}

/// Renders the draft through the genuine `QuizAnsweringCard` the feed uses,
/// over the video's own thumbnail — so what the creator checks is what the
/// learner will actually get, not a re-creation that can drift.
private struct QuizPreviewSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let video: Video
    let quiz: Quiz
    @StateObject private var page: FeedPageViewModel

    init(video: Video, quiz: Quiz) {
        self.video = video
        self.quiz = quiz
        _page = StateObject(wrappedValue: FeedPageViewModel(video: video, source: .continueTopic))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.black
                    }
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                }

                if let question = page.currentQuestion() {
                    QuizAnsweringCard(page: page, question: question, onAdvance: { page.advancePreview() })
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 12)
                } else {
                    Text("Add a question to preview it.")
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            .task { page.startPreview(with: quiz) }
        }
    }
}
