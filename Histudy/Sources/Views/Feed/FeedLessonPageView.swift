import SwiftUI

/// One full-screen page of the vertical feed. Lifecycle:
/// watching (lesson plays, narration captioned) → quiz (one or two
/// questions for this lesson, graded into SM-2) → done (nudge to swipe on).
/// Only the visible page plays; scrolling away pauses it.
struct FeedLessonPageView: View {
    let entry: FeedEntry
    let lesson: LessonScript
    let isActive: Bool
    @ObservedObject var feedVM: FeedViewModel

    @EnvironmentObject private var appState: AppState
    @StateObject private var lessonVM: LessonPlaybackViewModel
    @StateObject private var videoController: VideoPlaybackController

    private enum PagePhase { case watching, quiz, done }
    @State private var phase: PagePhase = .watching
    @State private var quizIndex = 0
    @State private var quizVM: QuizViewModel?
    @State private var showingInfo = false
    @State private var showingChat = false
    @State private var showingUpgrade = false

    init(entry: FeedEntry, lesson: LessonScript, isActive: Bool, feedVM: FeedViewModel, narrator: SpeechNarrator) {
        self.entry = entry
        self.lesson = lesson
        self.isActive = isActive
        self.feedVM = feedVM
        _lessonVM = StateObject(wrappedValue: LessonPlaybackViewModel(
            script: lesson,
            narrator: narrator
        ))
        _videoController = StateObject(wrappedValue: VideoPlaybackController(url: lesson.resolvedVideoURL))
    }

    private var language: AppLanguage { appState.profile.uiLanguage }
    private var quizQuestions: [CivicsQuestion] { feedVM.quizQuestions(for: entry) }
    /// Whether this page has a real produced/placeholder video to play
    /// instead of the procedural whiteboard scene renderer.
    private var isVideoBacked: Bool { lesson.resolvedVideoURL != nil }
    private var progressFraction: Double { isVideoBacked ? videoController.progressFraction : lessonVM.progressFraction }

    var body: some View {
        ZStack {
            if isVideoBacked {
                VideoPlayerLayerView(player: videoController.player)
                    .ignoresSafeArea()
            } else {
                Theme.scene.canvas.ignoresSafeArea()
            }

            VStack(spacing: 12) {
                ProgressView(value: progressFraction)
                    .tint(Theme.shell.gradientStart)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if !isVideoBacked {
                    SceneCanvasView(actions: lessonVM.activeActions, language: language)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }

            bottomOverlay
            actionRail

            if phase == .quiz {
                quizOverlay
            }
            if phase == .done {
                doneOverlay
            }
        }
        .clipped()
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                startPlayback()
            } else {
                pausePlayback()
            }
        }
        .onChange(of: lessonVM.isFinished) { _, finished in
            guard !isVideoBacked, finished, phase == .watching else { return }
            startQuiz()
        }
        .onChange(of: videoController.isFinished) { _, finished in
            guard isVideoBacked, finished, phase == .watching else { return }
            startQuiz()
        }
        .onAppear {
            if isActive {
                startPlayback()
            }
        }
        .onDisappear { pausePlayback() }
        .sheet(isPresented: $showingInfo) {
            LessonInfoSheet(lesson: lesson)
        }
        .sheet(isPresented: $showingChat) {
            TutorChatView(lesson: lesson)
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradePromptView()
        }
    }

    // MARK: - Overlays

    private var bottomOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language == .vietnamese ? lesson.titleVI : lesson.titleEN)
                        .font(.headline)
                        .foregroundStyle(Theme.scene.stroke)
                    if !isVideoBacked, phase == .watching, let beat = lessonVM.activeNarration {
                        Text(beat.text(for: language))
                            .font(.subheadline)
                            .foregroundStyle(Theme.scene.stroke.opacity(0.8))
                            .lineLimit(3)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                )
                Spacer(minLength: 70)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var actionRail: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                railButton(symbol: "info.circle.fill", label: L10n.feedInfoButton.localized) {
                    showingInfo = true
                }
                railButton(symbol: "sparkles", label: L10n.feedAskAI.localized) {
                    if appState.profile.isPro {
                        showingChat = true
                    } else {
                        showingUpgrade = true
                    }
                }
                railButton(symbol: "arrow.clockwise", label: L10n.lessonReplay.localized) {
                    phase = .watching
                    quizIndex = 0
                    quizVM = nil
                    if isVideoBacked {
                        videoController.restart()
                    } else {
                        lessonVM.restart(language: language)
                    }
                }
            }
            .padding(.trailing, 14)
            .padding(.bottom, 110)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func railButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.scene.stroke)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.scene.stroke.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }

    private var quizOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 0) {
                if let quizVM {
                    ScrollView {
                        QuizView(
                            quizVM: quizVM,
                            language: language,
                            onSubmit: {
                                feedVM.recordAnswer(
                                    entry: entry,
                                    questionID: quizVM.question.id,
                                    wasCorrect: quizVM.isCorrect
                                )
                            },
                            onContinue: advanceQuiz
                        )
                    }
                }
            }
            .frame(maxHeight: 460)
            .background(
                RoundedRectangle(cornerRadius: Theme.shell.cornerRadiusLarge, style: .continuous)
                    .fill(Theme.shell.canvas)
                    .shadow(radius: 12)
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .transition(.move(edge: .bottom))
    }

    private var doneOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(L10n.feedSwipeForNext.localized)
                .font(.headline)
                .foregroundStyle(Theme.shell.ink)
            Image(systemName: "chevron.up")
                .font(.title3)
                .foregroundStyle(Theme.shell.metadata)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: Theme.shell.cornerRadiusLarge, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .shadow(radius: 10)
        )
    }

    // MARK: - Playback

    private func startPlayback() {
        if isVideoBacked {
            videoController.play()
        } else {
            lessonVM.play(language: language)
        }
    }

    private func pausePlayback() {
        if isVideoBacked {
            videoController.pause()
        } else {
            lessonVM.pause()
        }
    }

    // MARK: - Quiz flow

    private func startQuiz() {
        guard !quizQuestions.isEmpty else {
            finishPage()
            return
        }
        quizIndex = 0
        quizVM = makeQuizVM(for: quizQuestions[0])
        withAnimation(.easeOut(duration: 0.3)) { phase = .quiz }
    }

    private func advanceQuiz() {
        let next = quizIndex + 1
        if next < quizQuestions.count {
            quizIndex = next
            quizVM = makeQuizVM(for: quizQuestions[next])
        } else {
            finishPage()
        }
    }

    private func finishPage() {
        feedVM.lessonCompleted(profile: appState.profile)
        withAnimation(.easeOut(duration: 0.3)) { phase = .done }
    }

    private func makeQuizVM(for question: CivicsQuestion) -> QuizViewModel {
        QuizViewModel(
            question: question,
            allQuestions: ContentStore.shared.questions,
            localOfficials: appState.profile.localOfficials
        )
    }
}
