import SwiftUI

/// Renders whichever `SceneAction`s are active at the current playback time
/// as a single composed "whiteboard" frame. Map-related actions (the base
/// map, region highlights, city pins) are layered together; every other
/// action type is treated as a standalone foreground beat.
struct SceneCanvasView: View {
    let actions: [SceneAction]
    let language: AppLanguage

    var body: some View {
        ZStack {
            if !mapActions.isEmpty {
                USMapView(
                    highlightedRegions: Set(regionActions.compactMap(\.region)),
                    regionLabels: regionLabels,
                    pins: pinActions.compactMap { action in
                        guard let city = action.cityName, let region = action.region else { return nil }
                        return MapPin(city: city, region: region)
                    }
                )
                .transition(.opacity)
            }

            ForEach(foregroundActions) { action in
                sceneElement(for: action)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: actions.map(\.id))
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.scene.canvas)
        )
    }

    private var mapActions: [SceneAction] { actions.filter { $0.type == .mapUSA } }
    private var regionActions: [SceneAction] { actions.filter { $0.type == .highlightRegion } }
    private var pinActions: [SceneAction] { actions.filter { $0.type == .dropPin } }

    private var foregroundActions: [SceneAction] {
        actions.filter { ![.mapUSA, .highlightRegion, .dropPin].contains($0.type) }
    }

    private var regionLabels: [USRegion: String] {
        Dictionary(uniqueKeysWithValues: regionActions.compactMap { action -> (USRegion, String)? in
            guard let region = action.region, let text = action.text(for: language) else { return nil }
            return (region, text)
        })
    }

    @ViewBuilder
    private func sceneElement(for action: SceneAction) -> some View {
        switch action.type {
        case .titleCard:
            TitleCardSceneView(text: action.text(for: language) ?? "", symbol: action.symbol)
        case .showIcon:
            IconCalloutView(symbol: action.symbol ?? "star", caption: action.text(for: language))
        case .bulletList:
            BulletListSceneView(items: action.items ?? [], language: language)
        case .documentReveal:
            DocumentRevealView(title: action.text(for: language) ?? "", symbol: action.symbol)
        case .timeline:
            TimelineBeatView(year: action.year ?? 0, label: action.text(for: language) ?? "")
        case .flagReveal:
            FlagRevealView()
        case .comparisonCards:
            ComparisonCardsView(items: action.items ?? [], language: language)
        case .quote:
            QuoteSceneView(text: action.text(for: language) ?? "")
        case .mapUSA, .highlightRegion, .dropPin:
            EmptyView()
        }
    }
}
