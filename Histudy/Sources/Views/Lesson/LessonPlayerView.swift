import SwiftUI

/// Plays one whiteboard-style lesson: a `SceneCanvasView` synced to
/// narration, with a caption bubble and a tappable logo mark that pulses
/// while the narrator is speaking. Tapping the logo opens lesson controls
/// (restart, skip, jump to a part) instead of the lesson being a passive,
/// linear-only video.
struct LessonPlayerView: View {
    @ObservedObject var lessonVM: LessonPlaybackViewModel
    @ObservedObject var narrator: SpeechNarrator
    let language: AppLanguage
    let onContinue: () -> Void

    @State private var showingMenu = false
    @State private var showingChapterPicker = false

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: lessonVM.progressFraction)
                .tint(Theme.shell.gradientStart)

            SceneCanvasView(actions: lessonVM.activeActions, language: language)

            if let narration = lessonVM.activeNarration {
                SpeechBubbleView(text: narration.text(for: language))
                    .id(narration.id)
                    .transition(.opacity)
            }

            Spacer()

            HStack(alignment: .bottom) {
                TutorLogoView(isSpeaking: narrator.isSpeaking)
                    .onTapGesture { showingMenu = true }
                    .accessibilityLabel(L10n.lessonMenuTitle.localized)
                    .accessibilityAddTraits(.isButton)
                Spacer()
                controls
            }
        }
        .padding()
        .histudyShellBackground()
        .onAppear { lessonVM.play(language: language) }
        .onDisappear { lessonVM.pause() }
        .confirmationDialog(L10n.lessonMenuTitle.localized, isPresented: $showingMenu, titleVisibility: .visible) {
            Button(L10n.lessonReplay.localized) {
                lessonVM.restart(language: language)
            }
            Button(L10n.lessonSkip.localized) {
                lessonVM.skipToEnd()
            }
            Button(L10n.lessonJumpToPart.localized) {
                showingChapterPicker = true
            }
            Button(L10n.cancel.localized, role: .cancel) {}
        }
        .sheet(isPresented: $showingChapterPicker) {
            ChapterPickerView(narration: lessonVM.script.narration, language: language) { beat in
                lessonVM.seek(to: beat.atSeconds, language: language)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if lessonVM.isFinished {
            Button(L10n.lessonContinueToQuiz.localized, action: onContinue)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.shell.gradientStart)
        } else {
            Button(L10n.lessonSkip.localized) {
                lessonVM.skipToEnd()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.shell.gradientEnd)
        }
    }
}
