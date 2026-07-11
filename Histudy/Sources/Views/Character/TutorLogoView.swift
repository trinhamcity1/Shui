import SwiftUI

/// The app's brand mark, standing in for the tutor character in the UI.
/// Deliberately abstract — no human illustration — per product direction:
/// a rounded, gradient logo mark (matching `Theme.shell`'s soft, rounded
/// aesthetic) that pulses gently while the narrator is speaking, instead of
/// an animated face/mouth.
struct TutorLogoView: View {
    var isSpeaking: Bool = false
    var emotion: CharacterEmotion = .neutral
    var size: CGFloat = 64

    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(Theme.shell.accentGradient)
                .frame(width: size, height: size)
                .shadow(color: Theme.shell.gradientEnd.opacity(isSpeaking ? 0.45 : 0), radius: pulse ? 12 : 5)
                .scaleEffect(pulse ? 1.06 : 1.0)

            Image(systemName: symbolName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(pulse ? 1.08 : 1.0)
        }
        .task(id: isSpeaking) {
            guard isSpeaking else { pulse = false; return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.5)) { pulse.toggle() }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: emotion)
    }

    private var symbolName: String {
        switch emotion {
        case .celebrating: return "sparkles"
        case .encouraging: return "heart.fill"
        case .thinking: return "ellipsis"
        case .happy, .neutral: return "star.fill"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        TutorLogoView(isSpeaking: false)
        TutorLogoView(isSpeaking: true, emotion: .celebrating)
    }
    .padding()
}
