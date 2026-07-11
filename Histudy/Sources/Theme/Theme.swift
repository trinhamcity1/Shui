import SwiftUI

/// Central design tokens for Histudy's two visual systems:
/// - `Theme.scene` styles the procedurally-rendered lesson "whiteboard" videos
///   (`SceneCanvasView` and friends) — a flat vector-art, hand-drawn-ink look.
/// - `Theme.shell` styles the surrounding app chrome (Home, Onboarding, Quiz,
///   Progress, Settings) — a warm, soft, highly-rounded look.
enum Theme {
    enum scene {
        /// Matte, off-white "physical whiteboard under studio light" canvas,
        /// rather than a stark digital white.
        static let canvas = Color(hex: 0xECECEC)
        /// Primary containers for informational/messaging content.
        static let accentBlue = Color(hex: 0x5BC5F2)
        /// Reserved *exclusively* for emotional/semantic emphasis (a key
        /// fact, a highlighted icon) — never used as a general accent.
        static let accentRed = Color(hex: 0xE11D48)
        /// All vector line-art strokes: map regions, icons, borders.
        static let stroke = Color(hex: 0x1E293B)
        static let strokeWidth: CGFloat = 2.5
        static let strokeStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    }

    enum shell {
        /// Warm off-white — soft and domestic rather than cold tech-white.
        static let canvas = Color(hex: 0xF4F3EF)
        static let ink = Color(hex: 0x1A1A1A)
        static let metadata = Color(hex: 0x6B7280)
        static let gradientStart = Color(hex: 0xF59E0B)
        static let gradientMid = Color(hex: 0xFBCB8B)
        static let gradientEnd = Color(hex: 0x818CF8)
        static let accentGradient = LinearGradient(
            colors: [gradientStart, gradientMid, gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let cornerRadiusLarge: CGFloat = 32
        static let cornerRadiusCard: CGFloat = 20
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// A soft, rounded card matching the Theme 2 shell aesthetic.
struct HistudyCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.shell.cornerRadiusCard, style: .continuous)
                    .fill(Color.white)
            )
    }
}

/// A pill-shaped button, filled with the gradient accent or outlined,
/// matching the Theme 2 "rounded-full" interactive pill spec.
struct HistudyPillButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(filled ? Color.white : Theme.shell.ink)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(filled ? Color.clear : Theme.shell.ink.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    @ViewBuilder
    private var background: some View {
        if filled {
            Theme.shell.accentGradient
        } else {
            Color.clear
        }
    }
}

extension ButtonStyle where Self == HistudyPillButtonStyle {
    static var histudyPill: HistudyPillButtonStyle { HistudyPillButtonStyle() }
    static var histudyPillOutline: HistudyPillButtonStyle { HistudyPillButtonStyle(filled: false) }
}

extension View {
    func histudyCard() -> some View { modifier(HistudyCardStyle()) }
    func histudyShellBackground() -> some View { background(Theme.shell.canvas.ignoresSafeArea()) }
}
