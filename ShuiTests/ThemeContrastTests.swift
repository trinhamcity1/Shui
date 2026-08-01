import SwiftUI
import UIKit
import XCTest
@testable import Shui

/// Verifies every semantic foreground/background pairing the app actually
/// draws meets WCAG 2.1 AA — 4.5:1 for text, 3:1 for large text and
/// non-text UI components (borders) — using the same relative-luminance math
/// as the spec, not a visual eyeball check.
///
/// Every test iterates `AppTheme.allCases`, so a theme added later (a
/// high-contrast variant, a seasonal palette) is checked by this exact same
/// suite the moment it's added to that enum — no new test code required.
final class ThemeContrastTests: XCTestCase {
    // MARK: - WCAG math

    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linearize(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        let lighter = max(l1, l2), darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func interpolate(_ a: Color, _ b: Color, _ t: Double) -> Color {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            .sRGB,
            red: Double(ar) + (Double(br) - Double(ar)) * t,
            green: Double(ag) + (Double(bg) - Double(ag)) * t,
            blue: Double(ab) + (Double(bb) - Double(ab)) * t,
            opacity: 1
        )
    }

    private func assertAA(
        _ fg: Color, _ bg: Color, minimum: Double = 4.5, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ratio = contrast(fg, bg)
        XCTAssertGreaterThanOrEqual(
            ratio, minimum,
            "\(label): \(String(format: "%.2f", ratio)):1, needs \(minimum):1",
            file: file, line: line
        )
    }

    // MARK: - Text

    func testTextPrimaryOnEverySurface() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            assertAA(t.textPrimary, t.canvas, "\(appTheme): textPrimary on canvas")
            assertAA(t.textPrimary, t.surface, "\(appTheme): textPrimary on surface")
            assertAA(t.textPrimary, t.surfaceSubtle, "\(appTheme): textPrimary on surfaceSubtle")
        }
    }

    func testTextSecondaryOnEverySurface() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            assertAA(t.textSecondary, t.canvas, "\(appTheme): textSecondary on canvas")
            assertAA(t.textSecondary, t.surface, "\(appTheme): textSecondary on surface")
        }
    }

    /// `textTertiary` is documented as large-text/icon-only — verified to
    /// the 3:1 large-text threshold, not 4.5:1.
    func testTextTertiaryAsLargeTextOnCanvas() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            assertAA(t.textTertiary, t.canvas, minimum: 3.0, "\(appTheme): textTertiary(large) on canvas")
        }
    }

    // MARK: - Accent

    func testAccentOnEverySurface() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            assertAA(t.accent, t.canvas, "\(appTheme): accent on canvas")
            assertAA(t.accent, t.surface, "\(appTheme): accent on surface")
        }
    }

    /// Samples every point along the gradient, not just its stops — a
    /// gradient's midpoint can dip below both endpoints' contrast.
    func testTextOnAccentAcrossTheFullGradient() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            let stops = t.accentGradientStops
            for i in 0..<(stops.count - 1) {
                for step in 0...8 {
                    let fraction = Double(step) / 8.0
                    let sampled = interpolate(stops[i], stops[i + 1], fraction)
                    assertAA(t.textOnAccent, sampled, "\(appTheme): textOnAccent @ segment \(i) fraction \(fraction)")
                }
            }
            assertAA(t.textOnAccent, t.accent, "\(appTheme): textOnAccent on solid accent fill")
        }
    }

    // MARK: - Structure

    /// WCAG 1.4.11 non-text contrast — 3:1 for UI component boundaries.
    func testFunctionalBorderMeetsNonTextContrast() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            assertAA(t.border, t.canvas, minimum: 3.0, "\(appTheme): border on canvas")
            assertAA(t.border, t.surface, minimum: 3.0, "\(appTheme): border on surface")
        }
    }

    // MARK: - Feedback

    func testFeedbackColorsOnEverySurface() {
        for appTheme in AppTheme.allCases {
            let t = appTheme.palette
            let feedback: [(String, Color)] = [
                ("success", t.success), ("warning", t.warning), ("error", t.error), ("info", t.info),
            ]
            for (name, color) in feedback {
                assertAA(color, t.canvas, "\(appTheme): \(name) on canvas")
                assertAA(color, t.surface, "\(appTheme): \(name) on surface")
            }
        }
    }
}
