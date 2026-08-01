import SwiftUI

/// A complete set of semantic color roles for one appearance (light, dark,
/// and whatever comes later). Every color in the app is meant to be reached
/// through one of these roles, never as a raw hex value at the call site —
/// that's what makes adding a new theme later (a high-contrast variant, a
/// seasonal palette, a user-selectable alternate) a matter of writing one
/// more conforming type, not hunting down every screen that hardcoded a
/// color.
///
/// Names describe *role*, not appearance — `surface`, not `white`;
/// `textSecondary`, not `gray`. A future dark-mode-native palette can (and
/// does) point `textOnAccent` at a completely different literal color than
/// the light palette's, and every call site stays correct without changes.
protocol ThemePalette {
    // MARK: Surfaces (background hierarchy, back to front)

    /// The app/page background — the base layer everything else sits on.
    var canvas: Color { get }
    /// Cards, sheets, and other content that sits visually above `canvas`.
    var surface: Color { get }
    /// Nested surfaces one level above `surface` — input fields, chips,
    /// selected-row backgrounds.
    var surfaceSubtle: Color { get }

    // MARK: Content (foreground hierarchy)

    /// Primary text and icons — headlines, body copy, primary labels.
    var textPrimary: Color { get }
    /// Secondary text — captions, metadata, timestamps.
    var textSecondary: Color { get }
    /// Tertiary text — placeholders and disabled state. Large text/icons
    /// (≥18pt regular or ≥14pt bold) only; verified to 3:1, not 4.5:1.
    var textTertiary: Color { get }
    /// Text and icons drawn on top of a filled `accent` surface (a solid
    /// accent-colored button, badge, or the accent gradient) — deliberately
    /// its own role rather than a fixed white/black, since the two themes'
    /// accent surfaces sit at different lightness and need opposite-toned
    /// text to stay legible.
    var textOnAccent: Color { get }

    // MARK: Brand / accent

    /// The solid brand accent — links, icon tints, the active tab indicator,
    /// small accent text. Verified against both `canvas` and `surface`.
    var accent: Color { get }
    /// The three-stop decorative gradient used on primary filled buttons and
    /// other large brand surfaces. Every stop (and points between them) is
    /// verified against `textOnAccent` at 4.5:1, not just the endpoints.
    var accentGradientStops: [Color] { get }

    // MARK: Structure

    /// Functional borders — input outlines, anything a learner needs to
    /// perceive as a distinct boundary. Verified to 3:1 (WCAG's non-text
    /// contrast minimum for UI components).
    var border: Color { get }
    /// Decorative-only hairlines and dividers that don't convey required
    /// structure on their own — not contrast-verified, and shouldn't be
    /// relied on as the only way to distinguish something.
    var borderSubtle: Color { get }

    // MARK: Feedback

    var success: Color { get }
    var warning: Color { get }
    var error: Color { get }
    var info: Color { get }

    // MARK: Overlay

    /// A dark translucent scrim over media (video gradient overlays, sheet
    /// backdrops). Not contrast-verified against a fixed background by
    /// design — it's a translucent layer over arbitrary content underneath,
    /// not a solid fill with known contrast.
    var scrim: Color { get }
}

extension ThemePalette {
    var accentGradient: LinearGradient {
        LinearGradient(colors: accentGradientStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
