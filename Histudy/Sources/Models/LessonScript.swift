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
///
/// A lesson can *also* carry a real produced video (Golpo-generated, or a
/// placeholder for infrastructure testing) via `videoURLString`/
/// `videoFileName`. Both are optional and absent from almost every lesson
/// today — see `resolvedVideoURL`. When present, the feed plays that video
/// via AVPlayer instead of the procedural scene renderer; when absent, the
/// existing SwiftUI renderer is the lesson, unchanged.
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
    /// A remote (e.g. S3/CDN) URL string for a real produced video. Takes
    /// priority over `videoFileName` when both are present.
    let videoURLString: String?
    /// Name of a video file bundled directly in the app (e.g. a placeholder
    /// used to test playback infrastructure before real videos exist).
    /// Looked up via `Bundle.main.url(forResource:withExtension:)`.
    let videoFileName: String?
}

extension LessonScript {
    /// Resolves to a real video source if this lesson has one: a remote
    /// URL first, else a bundled placeholder file, else nil (meaning:
    /// render the procedural whiteboard scene as usual).
    var resolvedVideoURL: URL? {
        if let videoURLString, let url = URL(string: videoURLString) {
            return url
        }
        if let videoFileName {
            let name = (videoFileName as NSString).deletingPathExtension
            let ext = (videoFileName as NSString).pathExtension
            return Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? "mp4" : ext)
        }
        return nil
    }
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
