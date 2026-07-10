import SwiftUI

/// Individual "whiteboard" scene elements. Each is a small, self-contained
/// SwiftUI view — together they're composed by `SceneCanvasView` into a
/// lesson's timeline. Built entirely from vector shapes and SF Symbols so no
/// external art assets are needed.

struct TitleCardSceneView: View {
    let text: String
    let symbol: String?

    var body: some View {
        VStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
            Text(text)
                .font(.title2.bold())
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
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            if let caption {
                Text(caption).font(.headline)
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
            ForEach(items, id: \.self) { item in
                Label(item.text(for: language), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
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
                Image(systemName: symbol).font(.system(size: 36))
            }
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.96, green: 0.93, blue: 0.83))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.brown.opacity(0.4), lineWidth: 2)
        )
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
                .background(Capsule().fill(Color.accentColor))
            Text(label).font(.headline)
        }
        .padding()
    }
}

struct ComparisonCardsView: View {
    let items: [SceneListItem]
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item.text(for: language))
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )
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
            .multilineTextAlignment(.center)
            .padding()
    }
}

/// A stylized, non-cartographic U.S. flag: 13 stripes and a grid of stars,
/// enough to teach the "13 stripes, 50 stars" civics fact visually.
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
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .padding()
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
/// cartographically precise state borders.
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
                ForEach(USRegion.allCases, id: \.self) { region in
                    if let frame = Self.layout[region] {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(color(for: region))
                            .frame(width: frame.w * geo.size.width, height: frame.h * geo.size.height)
                            .position(x: frame.x * geo.size.width, y: frame.y * geo.size.height)
                    }
                }

                ForEach(pins) { pin in
                    if let frame = Self.layout[pin.region] {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            Text(pin.city)
                                .font(.caption2.bold())
                        }
                        .position(x: frame.x * geo.size.width, y: frame.y * geo.size.height)
                    }
                }

                ForEach(Array(regionLabels.keys), id: \.self) { region in
                    if let frame = Self.layout[region], let label = regionLabels[region] {
                        Text(label)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .position(
                                x: frame.x * geo.size.width,
                                y: max(14, frame.y * geo.size.height - frame.h * geo.size.height / 2 - 12)
                            )
                    }
                }
            }
        }
        .frame(height: 220)
        .padding()
    }

    private func color(for region: USRegion) -> Color {
        highlightedRegions.contains(region) ? Color.accentColor : Color.gray.opacity(0.22)
    }
}
