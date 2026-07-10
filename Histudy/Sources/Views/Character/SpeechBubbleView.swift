import SwiftUI

/// A simple speech-bubble caption shown next to `TutorCharacterView`.
struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(alignment: .bottomLeading) {
                Triangle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 16, height: 10)
                    .offset(x: 20, y: 9)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Character portrait + speech bubble, the recurring "tutor speaks" unit
/// used across onboarding, home, and session summary screens.
struct TutorSpeechView: View {
    let message: TutorMessage
    let language: AppLanguage
    var isSpeaking: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TutorCharacterView(emotion: message.emotion, isSpeaking: isSpeaking)
                .frame(width: 90, height: 105)
                .scaleEffect(0.5, anchor: .top)
            SpeechBubbleView(text: message.text(for: language))
        }
    }
}

#Preview {
    TutorSpeechView(
        message: TutorMessage(textEN: "Welcome back!", textVI: "Chào mừng bạn quay lại!", emotion: .happy),
        language: .vietnamese
    )
    .padding()
}
