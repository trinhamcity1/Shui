import SwiftUI

/// The one-shot bloom that plays over the Generate button the moment it's
/// tapped: a glow ripple expanding outward from the button's own capsule,
/// plus a ring of twinkles thrown off its edges. Purely decorative —
/// overlaid with hit testing off, and keyed to `trigger` so each tap
/// replays it from the start.
struct GenerateBurst: View {
    let trigger: Int
    let colors: [Color]

    private static let twinkleAngles: [Double] = (0..<10).map { Double($0) * (2 * .pi / 10) + 0.3 }

    var body: some View {
        // Captured as plain values: the animator's content closure is @Sendable.
        let palette = colors
        let angles = Self.twinkleAngles
        Color.clear
            .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { content, frame in
                ZStack {
                    content
                    Capsule()
                        .fill(LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing))
                        .blur(radius: 18)
                        .opacity(frame.glowOpacity)
                    Capsule()
                        .stroke(LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing), lineWidth: 2)
                        .scaleEffect(x: 1 + 0.12 * frame.ripple, y: 1 + 1.1 * frame.ripple)
                        .opacity(frame.rippleOpacity)
                    ForEach(Array(angles.enumerated()), id: \.offset) { index, angle in
                        Twinkle()
                            .fill(palette.isEmpty ? Color.white : palette[index % palette.count])
                            .frame(width: index.isMultiple(of: 2) ? 12 : 8, height: index.isMultiple(of: 2) ? 12 : 8)
                            .scaleEffect(frame.twinkleScale)
                            // Elliptical spread — the button is far wider than it is tall.
                            .offset(x: CGFloat(cos(angle)) * frame.twinkleDistance * 1.9,
                                    y: CGFloat(sin(angle)) * frame.twinkleDistance)
                            .opacity(frame.twinkleOpacity)
                    }
                }
            } keyframes: { _ in
                KeyframeTrack(\.glowOpacity) {
                    LinearKeyframe(0.75, duration: 0.08)
                    CubicKeyframe(0, duration: 0.5)
                }
                KeyframeTrack(\.ripple) {
                    CubicKeyframe(1, duration: 0.6)
                }
                KeyframeTrack(\.rippleOpacity) {
                    LinearKeyframe(0.9, duration: 0.05)
                    CubicKeyframe(0, duration: 0.55)
                }
                KeyframeTrack(\.twinkleDistance) {
                    SpringKeyframe(64, duration: 0.6, spring: .smooth)
                }
                KeyframeTrack(\.twinkleScale) {
                    SpringKeyframe(1.15, duration: 0.25, spring: .bouncy)
                    CubicKeyframe(0.2, duration: 0.4)
                }
                KeyframeTrack(\.twinkleOpacity) {
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.24)
                    CubicKeyframe(0, duration: 0.34)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Every value starts invisible, so nothing shows before the first tap or
/// after the last one finishes.
private struct BurstFrame {
    var glowOpacity: Double = 0
    var ripple: CGFloat = 0
    var rippleOpacity: Double = 0
    var twinkleDistance: CGFloat = 0
    var twinkleScale: CGFloat = 0.2
    var twinkleOpacity: Double = 0
}

/// A four-point star.
private struct Twinkle: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.3
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The generating state's centerpiece: a slowly turning, breathing
/// gradient orb with soft rings drifting outward from it, like sonar.
/// Driven by wall-clock time rather than state, so it never stutters
/// across the view updates polling triggers, and it holds still under
/// Reduce Motion.
struct LessonOrb: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            orb(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: 200, height: 200)
        .accessibilityHidden(true)
    }

    private func orb(at t: TimeInterval) -> some View {
        let loop = colors + Array(colors.prefix(1))
        let breath = sin(t * 1.4)
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                let progress = (t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    .padding(28)
                    .scaleEffect(1 + progress * 0.7)
                    .opacity((1 - progress) * 0.55)
            }
            Circle()
                .fill(AngularGradient(colors: loop, center: .center, angle: .degrees(t * 36)))
                .padding(28)
                .blur(radius: 24)
                .scaleEffect(1 + 0.05 * breath)
            Circle()
                .fill(AngularGradient(colors: Array(loop.reversed()), center: .center, angle: .degrees(-t * 52)))
                .padding(52)
                .blur(radius: 12)
                .blendMode(.plusLighter)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: UnitPoint(x: 0.38, y: 0.34), startRadius: 2, endRadius: 64))
                .padding(48)
        }
        .compositingGroup()
    }
}
