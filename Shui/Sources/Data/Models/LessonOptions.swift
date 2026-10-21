import CoreGraphics
import Foundation

/// Mirror of `LESSON_DURATIONS` in functions/src/lib/tiers.ts — raw values
/// are minutes, spelled exactly as the server expects. Display-only: the
/// server re-checks the tier cap and recomputes the price itself.
enum LessonDuration: String, CaseIterable, Identifiable {
    case thirtySeconds = "0.5"
    case oneMinute = "1"
    case ninetySeconds = "1.5"
    case twoMinutes = "2"

    var id: String { rawValue }

    var minutes: Double {
        switch self {
        case .thirtySeconds: return 0.5
        case .oneMinute: return 1
        case .ninetySeconds: return 1.5
        case .twoMinutes: return 2
        }
    }

    var label: String {
        switch self {
        case .thirtySeconds: return "30s"
        case .oneMinute: return "1 min"
        case .ninetySeconds: return "1m 30s"
        case .twoMinutes: return "2 min"
        }
    }

    var spokenLabel: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .ninetySeconds: return "1 minute 30 seconds"
        case .twoMinutes: return "2 minutes"
        }
    }
}

/// The renderer's only two real output sizes — see `LessonFormat` for why
/// there's nothing finer-grained than this.
enum LessonOrientation: String {
    case vertical, horizontal

    /// Width ÷ height.
    var aspectRatio: CGFloat {
        switch self {
        case .vertical: return 2.0 / 3.0
        case .horizontal: return 3.0 / 2.0
        }
    }

    var pixelSize: String {
        switch self {
        case .vertical: return "1024 × 1536"
        case .horizontal: return "1536 × 1024"
        }
    }
}

/// What the learner picks on the New Lesson screen. The platform presets
/// are labels over the renderer's two real sizes, not distinct renders:
/// "TikTok" produces exactly what "Vertical" does. The renderer has no
/// width/height parameter, so a custom size isn't offered at all.
enum LessonFormat: String, CaseIterable, Identifiable {
    case vertical, horizontal
    case tiktok, instagramReels, facebookReels, youtubeShorts, youtube

    static let basics: [LessonFormat] = [.vertical, .horizontal]
    static let platforms: [LessonFormat] = [.tiktok, .instagramReels, .facebookReels, .youtubeShorts, .youtube]

    var id: String { rawValue }

    var orientation: LessonOrientation {
        switch self {
        case .vertical, .tiktok, .instagramReels, .facebookReels, .youtubeShorts: return .vertical
        case .horizontal, .youtube: return .horizontal
        }
    }

    var isPlatformPreset: Bool { Self.platforms.contains(self) }

    var title: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        case .tiktok: return "TikTok"
        case .instagramReels: return "Instagram Reels"
        case .facebookReels: return "Facebook Reels"
        case .youtubeShorts: return "YouTube Shorts"
        case .youtube: return "YouTube"
        }
    }

    var detail: String {
        isPlatformPreset ? "\(orientation == .vertical ? "Vertical" : "Horizontal") · \(orientation.pixelSize)" : orientation.pixelSize
    }
}
