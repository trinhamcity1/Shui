import SwiftUI

/// The MVP's single tutor character, drawn entirely with SwiftUI shapes so
/// the app ships with no external character art. Blinking and a talking
/// mouth are driven by `.task` loops tied to the view's lifetime rather than
/// stored Timers, so they start/stop cleanly as the view appears/disappears.
struct TutorCharacterView: View {
    var emotion: CharacterEmotion = .neutral
    var isSpeaking: Bool = false

    @State private var isBlinking = false
    @State private var mouthOpen = false

    private let skinTone = Color(red: 0.98, green: 0.85, blue: 0.72)
    private let hairColor = Color(red: 0.20, green: 0.15, blue: 0.13)
    private let accentColor = Color(red: 0.80, green: 0.20, blue: 0.24)
    private let mouthColor = Color(red: 0.55, green: 0.16, blue: 0.19)

    var body: some View {
        ZStack {
            collar
            head
            hairBack
            face
        }
        .frame(width: 180, height: 210)
        .task { await runBlinkLoop() }
        .task(id: isSpeaking) { await runMouthLoop() }
        .animation(.easeInOut(duration: 0.4), value: emotion)
    }

    private var collar: some View {
        VStack {
            Spacer()
            Capsule()
                .fill(accentColor)
                .frame(width: 130, height: 70)
        }
        .frame(height: 210)
    }

    private var hairBack: some View {
        Circle()
            .fill(hairColor)
            .frame(width: 150, height: 150)
            .offset(y: -6)
    }

    private var head: some View {
        Circle()
            .fill(skinTone)
            .frame(width: 118, height: 118)
            .offset(y: 6)
    }

    private var face: some View {
        VStack(spacing: 12) {
            eyebrows
            eyes
            mouth
        }
        .offset(y: 10)
    }

    private var eyebrows: some View {
        HStack(spacing: 26) {
            EyebrowShape(emotion: emotion)
                .stroke(hairColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 24, height: 10)
            EyebrowShape(emotion: emotion)
                .stroke(hairColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 24, height: 10)
                .scaleEffect(x: -1, y: 1)
        }
    }

    private var eyes: some View {
        HStack(spacing: 28) {
            eye
            eye
        }
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: 12, height: isBlinking ? 1.5 : 14)
    }

    private var mouth: some View {
        MouthShape(emotion: emotion, isOpen: mouthOpen)
            .fill(mouthColor)
            .frame(width: 38, height: mouthHeight)
    }

    private var mouthHeight: CGFloat {
        switch emotion {
        case .celebrating: return mouthOpen ? 22 : 14
        default: return mouthOpen ? 16 : 8
        }
    }

    private func runBlinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 0.08)) { isBlinking = true }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeInOut(duration: 0.08)) { isBlinking = false }
        }
    }

    private func runMouthLoop() async {
        guard isSpeaking else {
            mouthOpen = false
            return
        }
        while !Task.isCancelled {
            mouthOpen.toggle()
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
        mouthOpen = false
    }
}

private struct EyebrowShape: Shape {
    var emotion: CharacterEmotion

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lift: CGFloat = emotion == .thinking ? 6 : (emotion == .happy || emotion == .celebrating ? 4 : 0)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - lift),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

private struct MouthShape: Shape {
    var emotion: CharacterEmotion
    var isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if emotion == .encouraging || emotion == .thinking {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            let depth: CGFloat = isOpen ? rect.height : rect.height * 0.4
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.minY + depth)
            )
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        TutorCharacterView(emotion: .happy, isSpeaking: false)
        TutorCharacterView(emotion: .celebrating, isSpeaking: true)
    }
    .padding()
}
