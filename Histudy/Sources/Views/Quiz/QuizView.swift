import SwiftUI

/// A multiple-choice quiz for one question. Grading happens entirely
/// on-device (`QuizGrader`) — no network round trip is needed to know if an
/// answer is right. The tutor's in-character reaction to the result is
/// layered on top by the parent view via `SessionViewModel.feedbackMessage`.
struct QuizView: View {
    @ObservedObject var quizVM: QuizViewModel
    let language: AppLanguage
    let onSubmit: () async -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(quizVM.question.questionEN)
                .font(.title3.bold())
                .foregroundStyle(Theme.shell.ink)

            if quizVM.isAnswerable {
                instructionText
                optionsList
                if quizVM.isSubmitted { feedbackBanner }
                primaryButton
            } else {
                infoCard
                primaryButton
            }
        }
        .padding()
    }

    private var instructionText: some View {
        let text = quizVM.requiredCorrectCount > 1
            ? String(format: L10n.quizSelectAnswerPlural.localized, quizVM.requiredCorrectCount)
            : L10n.quizSelectAnswer.localized
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.shell.metadata)
    }

    private var optionsList: some View {
        VStack(spacing: 10) {
            ForEach(quizVM.options) { option in
                optionRow(option)
            }
        }
    }

    private func optionRow(_ option: QuizOption) -> some View {
        Button {
            quizVM.toggle(option)
        } label: {
            HStack {
                Text(option.text)
                    .foregroundStyle(Theme.shell.ink)
                Spacer()
                if quizVM.selected.contains(option) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.shell.gradientStart)
                }
            }
            .padding()
            .background(rowBackground(option), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(quizVM.isSubmitted)
    }

    private func rowBackground(_ option: QuizOption) -> Color {
        guard quizVM.isSubmitted else {
            return quizVM.selected.contains(option)
                ? Theme.shell.gradientStart.opacity(0.15)
                : Color.white
        }
        if option.isCorrect { return Color.green.opacity(0.2) }
        if quizVM.selected.contains(option) { return Color.red.opacity(0.2) }
        return Color.white
    }

    private var feedbackBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: quizVM.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(quizVM.isCorrect ? .green : .red)
            VStack(alignment: .leading, spacing: 4) {
                Text(quizVM.isCorrect ? L10n.quizCorrect.localized : L10n.quizIncorrect.localized)
                    .font(.headline)
                    .foregroundStyle(Theme.shell.ink)
                if !quizVM.isCorrect {
                    Text("\(L10n.quizCorrectAnswerWas.localized) \(quizVM.correctAnswerSummary)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.shell.metadata)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .histudyCard()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.quizNeedsProfileInfo.localized)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.metadata)
            Text(L10n.quizGoToSettings.localized)
                .font(.caption)
                .foregroundStyle(Theme.shell.metadata.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .histudyCard()
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !quizVM.isAnswerable {
            Button(L10n.continueLabel.localized) {
                Task {
                    await onSubmit()
                    onContinue()
                }
            }
            .buttonStyle(.histudyPill)
        } else if quizVM.isSubmitted {
            Button(L10n.quizNextQuestion.localized, action: onContinue)
                .buttonStyle(.histudyPill)
        } else {
            Button(L10n.quizSubmit.localized) {
                quizVM.submit()
                Task { await onSubmit() }
            }
            .buttonStyle(.histudyPill)
            .disabled(!quizVM.canSubmit)
        }
    }
}
