import AVFoundation
import SwiftUI

/// A `UIView` whose backing layer *is* an `AVPlayerLayer`, so the video
/// fills the view with no system playback chrome (no `AVPlayerViewController`
/// controls) — the feed's own overlay (progress bar, caption, action rail)
/// is the only UI on top of it.
final class PlayerLayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Chrome-less video surface for a feed page. `gravity` defaults to
/// `.resizeAspect` (shows the whole frame, letterboxed) — GolpoAI's real
/// output ratio (2:3, confirmed against their docs) doesn't match a phone
/// screen, and `.resizeAspectFill` was tried and rolled back for cropping
/// real content off the top/bottom. `gravity` stays a parameter rather than
/// a hardcoded value since not every caller necessarily wants the same
/// trade-off.
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.backgroundColor = .clear
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = gravity
    }
}
