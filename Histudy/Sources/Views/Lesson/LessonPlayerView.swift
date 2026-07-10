import SwiftUI

/// Plays one whiteboard-style lesson: a `SceneCanvasView` synced to
/// narration, with a caption bubble and a tutor character whose mouth
/// animates while the narrator is actually speaking.
struct LessonPlayerView: View {
    @ObservedObject var lessonVM: LessonPlaybackViewModel
    @ObservedObject var narrator: SpeechNarrator
    let language: AppLanguage
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: lessonVM.progressFraction)
                .tint(.accentColor)

            SceneCanvasView(actions: lessonVM.activeActions, language: language)

            if let narration = lessonVM.activeNarration {
                SpeechBubbleView(text: narration.text(for: language))
                    .id(narration.id)
                    .transition(.opacity)
            }

            Spacer()

            HStack(alignment: .bottom) {
                TutorCharacterView(emotion: .neutral, isSpeaking: narrator.isSpeaking)
                    .scaleEffect(0.55)
                    .frame(width: 100, height: 115)
                Spacer()
                controls
            }
        }
        .padding()
        .onAppear { lessonVM.play(language: language) }
        .onDisappear { lessonVM.pause() }
    }

    @ViewBuilder
    private var controls: some View {
        if lessonVM.isFinished {
            Button(L10n.lessonContinueToQuiz.localized, action: onContinue)
                .buttonStyle(.borderedProminent)
        } else {
            Button(L10n.lessonSkip.localized) {
                lessonVM.skipToEnd()
            }
            .buttonStyle(.bordered)
        }
    }
}
