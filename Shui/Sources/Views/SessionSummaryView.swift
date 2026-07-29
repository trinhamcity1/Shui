import SwiftUI

struct SessionSummaryView: View {
    @ObservedObject var sessionVM: SessionViewModel
    let language: AppLanguage
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TutorLogoView(emotion: .celebrating, size: 88)
            if let message = sessionVM.summaryMessage {
                SpeechBubbleView(text: message.text(for: language))
            }
            if let log = sessionVM.summaryLog {
                VStack(spacing: 8) {
                    statRow(label: L10n.summaryQuestionsAnswered.localized, value: "\(log.questionsAnswered)")
                    statRow(label: L10n.summaryAccuracy.localized, value: accuracyText(log))
                }
                .shuiCard()
            }
            Spacer()
            Button(L10n.summaryDone.localized, action: onDone)
                .buttonStyle(.shuiPill)
        }
        .padding()
        .shuiShellBackground()
        .navigationTitle(L10n.summaryTitle.localized)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.shell.metadata)
            Spacer()
            Text(value)
                .bold()
                .foregroundStyle(Theme.shell.ink)
        }
    }

    private func accuracyText(_ log: SessionLog) -> String {
        guard log.questionsAnswered > 0 else { return "—" }
        let percent = Int((Double(log.questionsCorrect) / Double(log.questionsAnswered) * 100).rounded())
        return "\(percent)%"
    }
}
