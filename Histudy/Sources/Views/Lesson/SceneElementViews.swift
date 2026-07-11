import SwiftUI

/// Individual "whiteboard" scene elements, styled to `Theme.scene`: a flat
/// vector-art look — matte canvas, sky-blue informational containers, red
/// reserved only for emotional/semantic emphasis, and uniform charcoal
/// 2-3px rounded-cap/join strokes mimicking hand-drawn digital ink. Each is
/// a small, self-contained SwiftUI view — together they're composed by
/// `SceneCanvasView` into a lesson's timeline. Built entirely from vector
/// shapes and SF Symbols so no external art assets are needed.

/// A stroke that "draws itself on" over `duration` seconds, the vector-art
/// equivalent of a whiteboard pen sketching a line, used throughout this
/// file for the staggered draw-in effect the theme calls for.
private struct DrawOnStroke: ViewModifier {
    var duration: Double = 0.6
    var delay: Double = 0
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(progress > 0 ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    progress = 1
                }
            }
    }
}

private extension View {
    func drawOn(duration: Double = 0.6, delay: Double = 0) -> some View {
        modifier(DrawOnStroke(duration: duration, delay: delay))
    }
}

struct TitleCardSceneView: View {
    let text: String
    let symbol: String?

    var body: some View {
        VStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.scene.stroke)
                    .drawOn()
            }
            Text(text)
                .font(.title2.bold())
                .foregroundStyle(Theme.scene.stroke)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct IconCalloutView: View {
    let symbol: String
    let caption: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Theme.scene.accentRed)
                .padding(20)
                .overlay(
                    Circle().stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle)
                )
                .drawOn()
            if let caption {
                Text(caption)
                    .font(.headline)
                    .foregroundStyle(Theme.scene.stroke)
            }
        }
        .padding()
    }
}

struct BulletListSceneView: View {
    let items: [SceneListItem]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Label {
                    Text(item.text(for: language))
                        .font(.headline)
                        .foregroundStyle(Theme.scene.stroke)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.scene.accentBlue)
                }
                .drawOn(delay: Double(index) * 0.15)
            }
        }
        .padding()
    }
}

struct DocumentRevealView: View {
    let title: String
    let symbol: String?

    var body: some View {
        VStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.scene.stroke)
            }
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.scene.stroke)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.scene.accentBlue.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle)
        )
        .drawOn()
    }
}

struct TimelineBeatView: View {
    let year: Int
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Text(String(year))
                .font(.title.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Theme.scene.accentBlue)
                        .overlay(Capsule().stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle))
                )
            Text(label)
                .font(.headline)
                .foregroundStyle(Theme.scene.stroke)
        }
        .padding()
        .drawOn()
    }
}

struct ComparisonCardsView: View {
    let items: [SceneListItem]
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item.text(for: language))
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.scene.stroke)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.scene.accentBlue.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle)
                    )
                    .drawOn(delay: Double(index) * 0.15)
            }
        }
        .padding()
    }
}

struct QuoteSceneView: View {
    let text: String

    var body: some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.title3.italic())
            .foregroundStyle(Theme.scene.stroke)
            .multilineTextAlignment(.center)
            .padding()
            .drawOn()
    }
}

/// A stylized, non-cartographic U.S. flag: 13 stripes and a grid of stars,
/// enough to teach the "13 stripes, 50 stars" civics fact visually. The
/// flag's own red/white/blue are the literal subject matter, not a theme
/// choice, but the outline follows the same charcoal vector-stroke treatment
/// as everything else in the scene.
struct FlagRevealView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<13, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.red : Color.white)
                    }
                }
                Rectangle()
                    .fill(Color(red: 0.10, green: 0.15, blue: 0.45))
                    .frame(width: geo.size.width * 0.4, height: geo.size.height * (7.0 / 13.0))
                starGrid
                    .frame(width: geo.size.width * 0.4, height: geo.size.height * (7.0 / 13.0))
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle)
        )
        .padding()
        .drawOn()
    }

    private var starGrid: some View {
        VStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(4)
    }
}

struct MapPin: Identifiable {
    let city: String
    let region: USRegion
    var id: String { city }
}

/// A schematic, illustrative map of the five U.S. regions used across the
/// geography and history lessons. Positions are stylized for teaching, not
/// cartographically precise state borders. Regions render as charcoal-
/// stroked vector shapes, filled sky-blue when highlighted.
struct USMapView: View {
    var highlightedRegions: Set<USRegion> = []
    var regionLabels: [USRegion: String] = [:]
    var pins: [MapPin] = []

    private static let layout: [USRegion: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        .west: (0.16, 0.50, 0.24, 0.72),
        .midwest: (0.44, 0.40, 0.22, 0.56),
        .northeast: (0.75, 0.26, 0.22, 0.40),
        .southwest: (0.40, 0.80, 0.28, 0.38),
        .southeast: (0.74, 0.74, 0.24, 0.48),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(USRegion.allCases.enumerated()), id: \.element) { index, region in
                    if let frame = Self.layout[region] {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(fill(for: region))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle)
                            )
                            .frame(width: frame.w * geo.size.width, height: frame.h * geo.size.height)
                            .position(x: frame.x * geo.size.width, y: frame.y * geo.size.height)
                            .drawOn(delay: Double(index) * 0.1)
                    }
                }

                ForEach(pins) { pin in
                    if let frame = Self.layout[pin.region] {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Theme.scene.accentRed)
                            Text(pin.city)
                                .font(.caption2.bold())
                                .foregroundStyle(Theme.scene.stroke)
                        }
                        .position(x: frame.x * geo.size.width, y: frame.y * geo.size.height)
                        .drawOn()
                    }
                }

                ForEach(Array(regionLabels.keys), id: \.self) { region in
                    if let frame = Self.layout[region], let label = regionLabels[region] {
                        Text(label)
                            .font(.caption.bold())
                            .foregroundStyle(Theme.scene.stroke)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Theme.scene.canvas)
                                    .overlay(Capsule().stroke(Theme.scene.stroke, style: Theme.scene.strokeStyle))
                            )
                            .position(
                                x: frame.x * geo.size.width,
                                y: max(14, frame.y * geo.size.height - frame.h * geo.size.height / 2 - 12)
                            )
                            .drawOn()
                    }
                }
            }
        }
        .frame(height: 220)
        .padding()
    }

    private func fill(for region: USRegion) -> Color {
        highlightedRegions.contains(region) ? Theme.scene.accentBlue.opacity(0.5) : Theme.scene.canvas
    }
}
