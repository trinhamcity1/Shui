import AVFoundation
import Combine
import Foundation

/// Drives a real `AVPlayer` for lessons that carry a produced (or
/// placeholder) video file, mirroring `LessonPlaybackViewModel`'s
/// play/pause/restart/seek surface so `FeedLessonPageView` can treat the
/// procedural whiteboard renderer and real video playback the same way.
/// When constructed with a `nil` URL, playback calls are no-ops — this
/// lets the feed page always hold one controller instead of an optional.
@MainActor
final class VideoPlaybackController: NSObject, ObservableObject {
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var isFinished = false

    let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL?) {
        if let url {
            player = AVPlayer(url: url)
        } else {
            player = AVPlayer()
        }
        super.init()
        guard url != nil else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let duration = self.player.currentItem?.duration, duration.seconds.isFinite, duration.seconds > 0 else { return }
            self.progressFraction = min(1, time.seconds / duration.seconds)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isFinished = true
        }
    }

    func play() {
        guard !isFinished else { return }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func restart() {
        isFinished = false
        progressFraction = 0
        player.seek(to: .zero)
        player.play()
    }

    /// Seeks to a fraction of total duration (used by the replay rail
    /// button's equivalent for procedural lessons; kept fraction-based so
    /// it doesn't need to know the video's real duration in seconds).
    func seek(toFraction fraction: Double) {
        guard let duration = player.currentItem?.duration, duration.seconds.isFinite, duration.seconds > 0 else { return }
        let clamped = max(0, min(1, fraction))
        let target = CMTime(seconds: clamped * duration.seconds, preferredTimescale: 600)
        isFinished = false
        player.seek(to: target) { [weak self] _ in
            self?.player.play()
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}
