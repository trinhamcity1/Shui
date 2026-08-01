import SwiftUI

/// Every appearance the app can render. `CaseIterable` on purpose —
/// `ThemeContrastTests` iterates this list, so a theme added here later
/// (a high-contrast variant, a seasonal palette) is verified by the same
/// suite automatically, with no test code to update.
enum AppTheme: String, CaseIterable {
    case light
    case dark

    var palette: ThemePalette {
        switch self {
        case .light: return LightPalette()
        case .dark: return DarkPalette()
        }
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = LightPalette()
}

extension EnvironmentValues {
    /// The active semantic palette. Read this, never `Theme.shell`-style
    /// globals or raw hex — that's what lets a view render correctly under
    /// any current or future theme without knowing which one is active.
    var theme: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension View {
    /// Resolves `AppTheme` from the system's light/dark setting and injects
    /// it as `\.theme`. Applied once at the app root (`ShuiApp.swift`) — a
    /// future user-selectable override (e.g. a "theme" preference in
    /// `UserProfile`) replaces the resolution rule inside this one modifier
    /// without touching any of the views that consume `\.theme`.
    func shuiTheme() -> some View {
        modifier(ShuiThemeModifier())
    }
}

private struct ShuiThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let resolved: AppTheme = colorScheme == .dark ? .dark : .light
        content.environment(\.theme, resolved.palette)
    }
}
