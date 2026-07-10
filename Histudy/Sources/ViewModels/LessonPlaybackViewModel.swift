import Combine
import Foundation

/// Drives playback of a `LessonScript`'s timeline: advances a clock, narrates
/// the active beat aloud, and exposes which scene actions should be on
/// screen right now. `SceneCanvasView` is a pure function of this state.
@MainActor
final class LessonPlaybackViewModel: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isFinished = false

    let script: LessonScript
    private let narrator: SpeechNarrator
    private var playbackTask: Task<Void, Never>?
    private var lastSpokenBeatID: String?

    init(script: LessonScript, narrator: SpeechNarrator) {
        self.script = script
        self.narrator = narrator
    }

    var activeActions: [SceneAction] {
        script.actions.filter { $0.timeRange.contains(currentTime) }
    }

    var activeNarration: NarrationBeat? {
        script.narration.first { $0.timeRange.contains(currentTime) }
    }

    var progressFraction: Double {
        guard script.totalDurationSeconds > 0 else { return 1 }
        return min(1, currentTime / script.totalDurationSeconds)
    }

    func play(language: AppLanguage) {
        guard !isPlaying, !isFinished else { return }
        isPlaying = true
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            let tick = 0.1
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                if Task.isCancelled { break }
                self.advance(by: tick, language: language)
                if self.currentTime >= self.script.totalDurationSeconds {
                    self.finish()
                    break
                }
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        narrator.stop()
    }

    func skipToEnd() {
        pause()
        currentTime = script.totalDurationSeconds
        isFinished = true
    }

    func restart(language: AppLanguage) {
        pause()
        currentTime = 0
        isFinished = false
        lastSpokenBeatID = nil
        play(language: language)
    }

    private func advance(by delta: Double, language: AppLanguage) {
        currentTime = min(script.totalDurationSeconds, currentTime + delta)
        if let beat = activeNarration, beat.id != lastSpokenBeatID {
            lastSpokenBeatID = beat.id
            narrator.speak(beat.text(for: language), language: language)
        }
    }

    private func finish() {
        isPlaying = false
        isFinished = true
    }
}
