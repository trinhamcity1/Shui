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

/// Full-bleed, chrome-less video surface for a feed page. Fills its frame
/// with `.resizeAspectFill`, matching the vertical, edge-to-edge look of
/// the rest of the TikTok-style feed.
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.backgroundColor = .clear
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
