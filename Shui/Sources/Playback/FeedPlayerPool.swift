import AVFoundation
import Foundation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case failed(Error)

    /// `Error` isn't `Equatable`, so this treats any two failures as equal —
    /// good enough for the UI's purposes (SwiftUI's `.onChange(of:)` needs
    /// `Equatable` to watch this at all; it never needs to compare *which*
    /// error two failures were).
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing),
             (.paused, .paused), (.ended, .ended), (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

enum PlaybackError: Error {
    case unknown
}

/// Owns a fixed ring of pooled `AVPlayer` instances so scrolling the feed
/// never allocates or tears down a player mid-scroll — the single biggest
/// source of jank in a video feed. Slots are recycled by feed index, not by
/// video id: `prepare` loads a URL into whichever pooled slot currently
/// holds an index that has fallen outside the caller's prefetch window.
@MainActor
final class FeedPlayerPool: ObservableObject {
    static let poolSize = 4

    @Published private(set) var states: [Int: PlaybackState] = [:]
    @Published private(set) var progress: [Int: Double] = [:]

    /// Fires on the main actor when the pooled player for `index` reaches
    /// the end of its item.
    var onEnded: ((Int) -> Void)?

    private final class Slot {
        let player = AVPlayer()
        var index: Int?
        var statusObservation: NSKeyValueObservation?
        var keepUpObservation: NSKeyValueObservation?
        var endObserver: NSObjectProtocol?
        var timeObserver: Any?
    }

    private var slots: [Slot] = (0..<FeedPlayerPool.poolSize).map { _ in Slot() }
    private var lastActiveIndex: Int?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        observeInterruptions()
    }

    func player(forIndex index: Int) -> AVPlayer? {
        slots.first { $0.index == index }?.player
    }

    /// A slot already showing `index` is left alone. Otherwise: reuse a free
    /// slot, or recycle whichever occupied slot's index falls outside
    /// `window`, or — if every slot is inside the window (shouldn't happen
    /// with a 4-wide pool and a 4-wide window, but never crash over it) —
    /// reuse the first slot.
    func prepare(index: Int, url: URL, window: ClosedRange<Int>) {
        if slots.contains(where: { $0.index == index }) { return }

        let reusable = slots.first(where: { $0.index == nil })
            ?? slots.first(where: { slot in
                guard let current = slot.index else { return true }
                return !window.contains(current)
            })
            ?? slots.first

        guard let slot = reusable else { return }

        detach(slot)
        slot.index = index
        states[index] = .loading
        progress[index] = 0

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        slot.player.automaticallyWaitsToMinimizeStalling = true
        slot.player.replaceCurrentItem(with: item)

        slot.statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleStatusChange(item: item, index: index)
            }
        }
        slot.keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleKeepUpChange(item: item, index: index)
            }
        }
        slot.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.states[index] = .ended
                self?.onEnded?(index)
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        slot.timeObserver = slot.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(index: index, time: time)
            }
        }
    }

    /// Plays the pooled player for `index`, pausing every other slot.
    func activate(index: Int) {
        lastActiveIndex = index
        for slot in slots {
            guard slot.index != index else { continue }
            slot.player.pause()
            if let otherIndex = slot.index, isPlaying(states[otherIndex]) {
                states[otherIndex] = .paused
            }
        }
        guard let slot = slots.first(where: { $0.index == index }) else { return }
        slot.player.play()
        states[index] = .playing
    }

    func pauseAll() {
        for slot in slots {
            slot.player.pause()
            if let idx = slot.index, isPlaying(states[idx]) {
                states[idx] = .paused
            }
        }
    }

    func togglePlayPause(index: Int) {
        guard let slot = slots.first(where: { $0.index == index }) else { return }
        if slot.player.timeControlStatus == .playing {
            slot.player.pause()
            states[index] = .paused
        } else {
            slot.player.play()
            states[index] = .playing
        }
    }

    func restart(index: Int) {
        guard let slot = slots.first(where: { $0.index == index }) else { return }
        states[index] = .loading
        slot.player.seek(to: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.states[index] = .playing
                slot.player.play()
            }
        }
    }

    /// Drops any pooled slot whose index has fallen outside `window` — keeps
    /// memory bounded without waiting for the next `prepare` to reclaim it.
    func recycle(outside window: ClosedRange<Int>) {
        for slot in slots {
            guard let idx = slot.index, !window.contains(idx) else { continue }
            detach(slot)
            states[idx] = nil
            progress[idx] = nil
        }
    }

    /// Detaches every pooled slot and clears all tracked state — for when the
    /// feed itself is rebuilt from scratch (pull-to-refresh), since old slot
    /// indices no longer correspond to anything once `pages` is replaced.
    func reset() {
        for slot in slots {
            detach(slot)
        }
        states = [:]
        progress = [:]
        lastActiveIndex = nil
    }

    private func isPlaying(_ state: PlaybackState?) -> Bool {
        if case .playing = state { return true }
        return false
    }

    private func detach(_ slot: Slot) {
        slot.player.pause()
        slot.player.replaceCurrentItem(with: nil)
        slot.statusObservation = nil
        slot.keepUpObservation = nil
        if let endObserver = slot.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            slot.endObserver = nil
        }
        if let timeObserver = slot.timeObserver {
            slot.player.removeTimeObserver(timeObserver)
            slot.timeObserver = nil
        }
        slot.index = nil
    }

    private func handleStatusChange(item: AVPlayerItem, index: Int) {
        switch item.status {
        case .readyToPlay:
            if case .loading = states[index] ?? .loading {
                states[index] = .paused
            }
        case .failed:
            states[index] = .failed(item.error ?? PlaybackError.unknown)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// `isPlaybackLikelyToKeepUp` toggling false while a video is actively
    /// playing is a mid-playback stall (bad network, etc.) — surface it as
    /// `.loading` distinctly from the initial load, and drop back to
    /// `.playing` once buffering recovers.
    private func handleKeepUpChange(item: AVPlayerItem, index: Int) {
        switch states[index] {
        case .playing where !item.isPlaybackLikelyToKeepUp:
            states[index] = .loading
        case .loading where item.isPlaybackLikelyToKeepUp:
            states[index] = .playing
        default:
            break
        }
    }

    private func updateProgress(index: Int, time: CMTime) {
        guard let slot = slots.first(where: { $0.index == index }),
              let duration = slot.player.currentItem?.duration,
              duration.seconds.isFinite, duration.seconds > 0
        else { return }
        progress[index] = min(1, max(0, time.seconds / duration.seconds))
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal — playback still works without the dedicated
            // category, just without foreground/silent-switch behavior
            // appropriate for a video app.
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            pauseAll()
        case .ended:
            guard
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
                let index = lastActiveIndex
            else { return }
            activate(index: index)
        @unknown default:
            break
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }
}
