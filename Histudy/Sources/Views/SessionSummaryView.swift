import SwiftUI

struct SessionSummaryView: View {
    @ObservedObject var sessionVM: SessionViewModel
    let language: AppLanguage
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TutorCharacterView(emotion: .celebrating, isSpeaking: false)
            if let message = sessionVM.summaryMessage {
                SpeechBubbleView(text: message.text(for: language))
            }
            if let log = sessionVM.summaryLog {
                VStack(spacing: 8) {
                    statRow(label: L10n.summaryQuestionsAnswered.localized, value: "\(log.questionsAnswered)")
                    statRow(label: L10n.summaryAccuracy.localized, value: accuracyText(log))
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            Button(L10n.summaryDone.localized, action: onDone)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .navigationTitle(L10n.summaryTitle.localized)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold()
        }
    }

    private func accuracyText(_ log: SessionLog) -> String {
        guard log.questionsAnswered > 0 else { return "—" }
        let percent = Int((Double(log.questionsCorrect) / Double(log.questionsAnswered) * 100).rounded())
        return "\(percent)%"
    }
}
