import SwiftUI

/// Every literal color in this file is verified against WCAG 2.1 AA by
/// `ShuiTests/ThemeContrastTests.swift`, which runs the same relative-
/// luminance math as the WCAG spec against every foreground/background
/// pairing the app actually uses (4.5:1 for text, 3:1 for large text/UI
/// components). Change a value here, re-run that suite before assuming it
/// still holds — the numbers aren't obvious from the hex alone.

/// Warm, soft, off-white — the light appearance.
struct LightPalette: ThemePalette {
    let canvas = Color(hex: 0xF4F3EF)
    let surface = Color(hex: 0xFFFFFF)
    let surfaceSubtle = Color(hex: 0xEAE8E1)

    let textPrimary = Color(hex: 0x1A1A1A)
    let textSecondary = Color(hex: 0x57534E)
    let textTertiary = Color(hex: 0x78716C)
    let textOnAccent = Color(hex: 0xFFFFFF)

    let accent = Color(hex: 0xB4530A)
    let accentGradientStops = [
        Color(hex: 0xB4530A),
        Color(hex: 0x9A4A6B),
        Color(hex: 0x4338CA),
    ]

    let border = Color(hex: 0x928B7C)
    let borderSubtle = Color(hex: 0xDDD9D0)

    let success = Color(hex: 0x15803D)
    let warning = Color(hex: 0x9A5B0A)
    let error = Color(hex: 0xB91C1C)
    let info = Color(hex: 0x1D4ED8)

    let scrim = Color.black.opacity(0.55)
}

/// Warm near-black — the dark appearance. Not a simple inversion of light:
/// the accent gradient is deliberately brighter/more saturated here (a deep
/// amber reads as muddy on a near-black canvas), which is why `textOnAccent`
/// flips to dark ink instead of staying white — verified per-theme, not
/// assumed.
struct DarkPalette: ThemePalette {
    let canvas = Color(hex: 0x18140F)
    let surface = Color(hex: 0x241E17)
    let surfaceSubtle = Color(hex: 0x2E271D)

    let textPrimary = Color(hex: 0xF5F1EA)
    let textSecondary = Color(hex: 0xB8AFA1)
    let textTertiary = Color(hex: 0x8C8375)
    let textOnAccent = Color(hex: 0x18140F)

    let accent = Color(hex: 0xF0A94E)
    let accentGradientStops = [
        Color(hex: 0xF0A94E),
        Color(hex: 0xE08FA8),
        Color(hex: 0x9CA3F5),
    ]

    let border = Color(hex: 0x827664)
    let borderSubtle = Color(hex: 0x3A3226)

    let success = Color(hex: 0x4ADE80)
    let warning = Color(hex: 0xF3B13C)
    let error = Color(hex: 0xF87171)
    let info = Color(hex: 0x60A5FA)

    let scrim = Color.black.opacity(0.55)
}
