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

    /// "a 1-minute lesson" phrasing.
    var adjective: String {
        switch self {
        case .thirtySeconds: return "30-second"
        case .oneMinute: return "1-minute"
        case .ninetySeconds: return "90-second"
        case .twoMinutes: return "2-minute"
        }
    }

    /// Mirrors `scriptCharBudget` in functions/src/lib/golpo.ts — the most
    /// narration this length can hold, in the UTF-16 units the server counts.
    var scriptCharacterBudget: Int {
        Int(minutes * 1050)
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

/// Mirrors `LESSON_MODES` in functions/src/lib/lessonSpec.ts.
enum LessonMode: String, CaseIterable, Identifiable {
    /// An idea or a detailed brief — Shui writes the script from it.
    case describe
    /// The learner's own narration, read word-for-word.
    case script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .describe: return "Describe"
        case .script: return "My script"
        }
    }

    var systemImage: String {
        switch self {
        case .describe: return "text.bubble"
        case .script: return "text.quote"
        }
    }
}

/// Mirrors `LESSON_PURPOSES` — shapes tone and structure, never facts.
enum LessonPurpose: String, CaseIterable, Identifiable {
    case personal
    case teamTraining = "team_training"
    case classroom
    case socialMedia = "social_media"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal"
        case .teamTraining: return "Team training"
        case .classroom: return "Class"
        case .socialMedia: return "Social media"
        }
    }

    var detail: String {
        switch self {
        case .personal: return "Learning for yourself"
        case .teamTraining: return "Onboarding, rules, steps"
        case .classroom: return "Students, step by step"
        case .socialMedia: return "A hook, one takeaway"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .teamTraining: return "person.3.fill"
        case .classroom: return "graduationcap.fill"
        case .socialMedia: return "megaphone.fill"
        }
    }
}

/// Raw values are the renderer's own voice ids (`GOLPO_VOICES`); `.auto`
/// is never sent — leaving it out lets Shui choose, as it always has.
enum LessonVoice: String, CaseIterable, Identifiable {
    case auto
    case warm = "female-1"
    case energetic = "female-2"
    case calm = "male-1"
    case dramatic = "male-2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .warm: return "Warm"
        case .energetic: return "Energetic"
        case .calm: return "Calm"
        case .dramatic: return "Dramatic"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Shui picks"
        case .warm, .energetic: return "Female"
        case .calm, .dramatic: return "Male"
        }
    }

    var systemImage: String {
        self == .auto ? "sparkles" : "waveform"
    }
}

/// Everything the New Lesson screen sends to `createOnDemandLesson`.
struct LessonRequest {
    var mode: LessonMode
    var text: String
    var duration: LessonDuration
    var orientation: LessonOrientation
    var purpose: LessonPurpose
    var voice: LessonVoice
}
