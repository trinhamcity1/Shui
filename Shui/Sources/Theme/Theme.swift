import SwiftUI

/// Non-color layout tokens shared across the app shell. Color tokens live in
/// `ThemePalette`/`AppTheme` instead — reached via `@Environment(\.theme)`,
/// never through a global like this, so they can vary per appearance.
enum Theme {
    static let cornerRadiusLarge: CGFloat = 32
    static let cornerRadiusCard: CGFloat = 20
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

/// A soft, rounded card matching the shell aesthetic.
struct ShuiCardStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                    .fill(theme.surface)
            )
    }
}

/// A pill-shaped button, filled with the gradient accent or outlined.
struct ShuiPillButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(filled ? theme.textOnAccent : theme.textPrimary)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(filled ? Color.clear : theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    @ViewBuilder
    private var background: some View {
        if filled {
            theme.accentGradient
        } else {
            Color.clear
        }
    }
}

extension ButtonStyle where Self == ShuiPillButtonStyle {
    static var shuiPill: ShuiPillButtonStyle { ShuiPillButtonStyle() }
    static var shuiPillOutline: ShuiPillButtonStyle { ShuiPillButtonStyle(filled: false) }
}

extension View {
    func shuiCard() -> some View { modifier(ShuiCardStyle()) }
    func shuiShellBackground() -> some View { modifier(ShuiShellBackgroundModifier()) }
}

private struct ShuiShellBackgroundModifier: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.canvas.ignoresSafeArea())
    }
}
