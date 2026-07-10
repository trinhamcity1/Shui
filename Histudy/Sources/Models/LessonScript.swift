import Foundation

/// Style of a lesson. Flagship lessons get a hand-authored, whiteboard-style
/// narrative timeline; every other question falls back to a short
/// auto-composed flashcard scene so the full 100-question bank always has a
/// narrated lesson, even before every question gets a bespoke script.
enum LessonStyle: String, Codable, Hashable {
    case richNarrative
    case quickFact
}

/// Stylized regions used by the map-drawing scene actions. These are
/// illustrative, not cartographically precise state borders.
enum USRegion: String, Codable, CaseIterable, Hashable {
    case northeast, southeast, midwest, southwest, west
}

enum SceneActionType: String, Codable, Hashable {
    case titleCard
    case mapUSA
    case highlightRegion
    case dropPin
    case showIcon
    case bulletList
    case documentReveal
    case timeline
    case flagReveal
    case comparisonCards
    case quote
}

struct SceneListItem: Codable, Hashable {
    let textEN: String
    let textVI: String
}

/// A single visual beat in a lesson's timeline, active while the playback
/// position falls at or after `atSeconds` and before `atSeconds + durationSeconds`.
struct SceneAction: Codable, Identifiable, Hashable {
    let id: String
    let type: SceneActionType
    let atSeconds: Double
    let durationSeconds: Double
    let textEN: String?
    let textVI: String?
    let symbol: String?
    let region: USRegion?
    let cityName: String?
    let year: Int?
    let items: [SceneListItem]?

    var timeRange: Range<Double> { atSeconds..<(atSeconds + durationSeconds) }
}

/// One spoken narration beat, delivered by the tutor character via
/// `SpeechNarrator` and shown as an on-screen caption.
struct NarrationBeat: Codable, Identifiable, Hashable {
    let id: String
    let textEN: String
    let textVI: String
    let atSeconds: Double
    let durationSeconds: Double

    var timeRange: Range<Double> { atSeconds..<(atSeconds + durationSeconds) }
}

/// A whiteboard-animation-style lesson: narration synced to procedurally
/// drawn scenes, rendered entirely in SwiftUI so it can be localized without
/// re-rendering video, and covering one or more related questions.
struct LessonScript: Codable, Identifiable, Hashable {
    let id: String
    let questionIds: [Int]
    let titleEN: String
    let titleVI: String
    let category: QuestionCategory
    let totalDurationSeconds: Double
    let narration: [NarrationBeat]
    let actions: [SceneAction]
    let style: LessonStyle
}

extension NarrationBeat {
    func text(for language: AppLanguage) -> String {
        language == .vietnamese ? textVI : textEN
    }
}

extension SceneListItem {
    func text(for language: AppLanguage) -> String {
        language == .vietnamese ? textVI : textEN
    }
}

extension SceneAction {
    /// Falls back to whichever language variant is actually present, since
    /// some scene actions only carry a symbol/region with no text.
    func text(for language: AppLanguage) -> String? {
        switch language {
        case .vietnamese: return textVI ?? textEN
        case .english: return textEN ?? textVI
        }
    }
}
