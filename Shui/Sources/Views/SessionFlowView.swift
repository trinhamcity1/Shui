import SwiftUI

/// Hosts a full daily session: lesson → quiz for each planned item, then a
/// summary. Pushed from `HomeView` when the learner taps "Start today's
/// session".
struct SessionFlowView: View {
    @StateObject private var sessionVM: SessionViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    init(items: [SessionItem], appState: AppState) {
        _sessionVM = StateObject(wrappedValue: SessionViewModel(
            items: items,
            profile: appState.profile,
            narrator: appState.narrator,
            tutorAI: appState.tutorAI
        ))
    }

    private var language: AppLanguage { appState.profile.uiLanguage }

    var body: some View {
        VStack(spacing: 0) {
            if sessionVM.phase != .summary {
                Text("\(sessionVM.index + 1) / \(sessionVM.totalCount)")
                    .font(.caption)
                    .foregroundStyle(Theme.shell.metadata)
                    .padding(.top, 8)
            }

            switch sessionVM.phase {
            case .lesson:
                if let lessonVM = sessionVM.lessonVM {
                    LessonPlayerView(
                        lessonVM: lessonVM,
                        narrator: sessionVM.narrator,
                        language: language,
                        onContinue: { sessionVM.lessonFinished() }
                    )
                }
            case .quiz:
                if let quizVM = sessionVM.quizVM {
                    ScrollView {
                        VStack(spacing: 16) {
                            QuizView(
                                quizVM: quizVM,
                                language: language,
                                onSubmit: { await sessionVM.quizAnswered() },
                                onContinue: { Task { await sessionVM.advance() } }
                            )
                            if let feedback = sessionVM.feedbackMessage {
                                TutorSpeechView(message: feedback, language: language)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .shuiShellBackground()
                }
            case .summary:
                SessionSummaryView(sessionVM: sessionVM, language: language, onDone: { dismiss() })
            }
        }
        .shuiShellBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sessionVM.phase != .summary)
    }
}
