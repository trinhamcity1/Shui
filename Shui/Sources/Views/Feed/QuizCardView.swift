import SwiftUI

/// The sheet-like overlay that slides up over the paused final frame once a
/// video ends — quiz answering, submission, per-question reveal, and the
/// final result, or a compact "lesson complete" strip when there's no quiz.
struct QuizOverlayContainer: View {
    @ObservedObject var page: FeedPageViewModel
    @ObservedObject var viewModel: FeedViewModel
    let reduceMotion: Bool
    let onNextLesson: () -> Void
    /// Keeps the card's actual buttons clear of the floating tab bar
    /// without shrinking the page behind it — see `FeedView`'s comment on
    /// why this has to be threaded down explicitly rather than read here
    /// via `@Environment` or `GeometryProxy.safeAreaInsets`.
    let tabBarBottomInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isPresented ? 0.55 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Group {
                    switch page.endState {
                    case .notEnded:
                        EmptyView()
                    case .loadingQuiz, .submitting:
                        loadingCard
                    case .noQuiz:
                        LessonCompleteStrip(
                            onNext: onNextLesson,
                            onReplay: { viewModel.replay(page) }
                        )
                    case .answering:
                        if let question = page.currentQuestion() {
                            QuizAnsweringCard(page: page, viewModel: viewModel, question: question)
                        }
                    case .submissionFailed(let message):
                        QuizSubmissionFailedCard(message: message, onRetry: { viewModel.retrySubmission(for: page) })
                    case .revealing:
                        if let reveal = page.revealForCurrentQuestion() {
                            QuizRevealCard(
                                question: reveal.question,
                                result: reveal.result,
                                selectedOptionIds: page.selectedOptionsByQuestion[reveal.question.id] ?? [],
                                onContinue: { page.advanceReveal() }
                            )
                        }
                    case .result:
                        QuizResultCard(page: page, onNext: onNextLesson, onReplay: { viewModel.replay(page) })
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, tabBarBottomInset)
                .frame(maxHeight: geo.size.height * 0.7, alignment: .bottom)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .bottom)
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(page.endState.transitionKey)
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85), value: page.endState.transitionKey)
        }
    }

    private var isPresented: Bool {
        page.endState != .notEnded
    }

    private var loadingCard: some View {
        ProgressView()
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
    }
}

private extension LessonEndState {
    /// A coarser key than full `Equatable` identity — used only to decide
    /// whether the overlay's slide/fade transition should replay, so
    /// stepping between `.answering` questions doesn't re-trigger the
    /// slide-up-from-nothing animation every question.
    var transitionKey: Int {
        switch self {
        case .notEnded: return 0
        case .loadingQuiz: return 1
        case .noQuiz: return 2
        case .answering: return 3
        case .submitting: return 4
        case .submissionFailed: return 5
        case .revealing: return 6
        case .result: return 7
        }
    }
}

// MARK: - Answering

private struct QuizAnsweringCard: View {
    @ObservedObject var page: FeedPageViewModel
    @ObservedObject var viewModel: FeedViewModel
    let question: QuizQuestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let number = page.questionNumber() {
                    Text("Question \(number.current) of \(number.total)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(question.prompt)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if question.requiredCorrectCount > 1 {
                    Text("Choose \(question.requiredCorrectCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(question.options) { option in
                        OptionRow(
                            text: option.text,
                            isSelected: page.isOptionSelected(option.id, for: question)
                        ) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            page.toggleOption(option.id, for: question)
                        }
                    }
                }

                Button(page.isLastQuestion() ? "Submit" : "Next") {
                    viewModel.advanceQuiz(for: page)
                }
                .buttonStyle(.shuiPill)
                .disabled(!page.canAdvance(question: question))
                .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct OptionRow: View {
    @Environment(\.theme) private var theme
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(16)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accent : .clear, lineWidth: 2)
            )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Submission failure

private struct QuizSubmissionFailedCard: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: message == nil ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Couldn't submit your answers")
                .font(.headline)
            Text(message ?? "Your answers are saved. We'll try again automatically, or you can retry now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.shuiPill)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Reveal

private struct QuizRevealCard: View {
    @Environment(\.theme) private var theme
    let question: QuizQuestion
    let result: QuizQuestionResult
    let selectedOptionIds: Set<String>
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: result.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.wasCorrect ? theme.success : theme.error)
                    Text(result.wasCorrect ? "Correct" : "Not quite")
                        .font(.headline)
                }

                Text(question.prompt)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    ForEach(question.options) { option in
                        RevealOptionRow(
                            text: option.text,
                            isSelected: selectedOptionIds.contains(option.id),
                            isCorrect: result.correctOptionIds.contains(option.id)
                        )
                    }
                }

                Text(result.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button("Continue", action: onContinue)
                    .buttonStyle(.shuiPill)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            if result.wasCorrect {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

private struct RevealOptionRow: View {
    @Environment(\.theme) private var theme
    let text: String
    let isSelected: Bool
    let isCorrect: Bool

    private var tint: Color {
        if isCorrect { return theme.success }
        if isSelected { return theme.error }
        return .primary.opacity(0.06)
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.body)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if isCorrect {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.success)
            } else if isSelected {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.error)
            }
        }
        .padding(16)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((isCorrect || isSelected) ? tint.opacity(0.18) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((isCorrect || isSelected) ? tint : .clear, lineWidth: 2)
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isCorrect { return "\(text), correct answer" }
        if isSelected { return "\(text), your answer, incorrect" }
        return text
    }
}

// MARK: - Result

private struct QuizResultCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var page: FeedPageViewModel
    let onNext: () -> Void
    let onReplay: () -> Void

    private var scorePercent: Int {
        guard let result = page.quizResult else { return 0 }
        return Int((result.score * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: (page.quizResult?.passed ?? false) ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle((page.quizResult?.passed ?? false) ? theme.success : theme.warning)

            Text((page.quizResult?.passed ?? false) ? "Passed" : "Keep practicing")
                .font(.title3.weight(.bold))

            Text("\(scorePercent)% correct")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let delta = page.masteryDelta, delta != 0 {
                Text("Topic mastery \(delta > 0 ? "+" : "")\(delta)%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(delta > 0 ? theme.success : .secondary)
            }

            VStack(spacing: 10) {
                Button("Next lesson", action: onNext)
                    .buttonStyle(.shuiPill)
                Button("Replay", action: onReplay)
                    .buttonStyle(.shuiPillOutline)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - No quiz

private struct LessonCompleteStrip: View {
    @Environment(\.theme) private var theme
    let onNext: () -> Void
    let onReplay: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label("Lesson complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(theme.success)
            Spacer()
            Button("Replay", action: onReplay)
                .buttonStyle(.shuiPillOutline)
            Button("Next lesson", action: onNext)
                .buttonStyle(.shuiPill)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
