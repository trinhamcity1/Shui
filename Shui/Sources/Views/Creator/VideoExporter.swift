import AVFoundation
import UIKit

/// What `AVAsset` can tell us about a picked file before anything is
/// uploaded — used to warn (never block) on shape, per
/// prompts/phase-05-creator-mode.md §4.2.
struct VideoInspection {
    var duration: Double
    var naturalSize: CGSize
    var sizeBytes: Int

    var aspectRatio: Double {
        guard naturalSize.height > 0 else { return 9.0 / 16.0 }
        return Double(naturalSize.width / naturalSize.height)
    }

    /// The feed is built for vertical video. 9:16 is 0.5625; anything within
    /// a reasonable band of that reads as portrait on a phone.
    var isRoughlyVertical: Bool { aspectRatio < 0.75 }
    var isOverLengthGuidance: Bool { duration > 600 }

    var warnings: [String] {
        var items: [String] = []
        if !isRoughlyVertical {
            items.append("This isn't a vertical video. It'll be letterboxed in the feed.")
        }
        if isOverLengthGuidance {
            items.append("This is over 10 minutes. Short lessons hold attention better.")
        }
        return items
    }
}

enum VideoExportError: LocalizedError {
    case unreadable
    case exportFailed(String)
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn't read that video file."
        case .noVideoTrack:
            return "That file has no video track."
        case .exportFailed(let message):
            return message
        }
    }
}

/// Local inspection, trimming, transcoding, and thumbnail extraction. Pure
/// AVFoundation, no Firebase — kept separate from the upload flow's view
/// model so the media work can be reasoned about (and, on a real Mac,
/// tested) without a network or a UI.
enum VideoExporter {
    static func inspect(url: URL) async throws -> VideoInspection {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        // Apply the track's transform before reporting size: a portrait
        // video recorded on a phone has a landscape `naturalSize` plus a
        // 90° transform, so reading naturalSize alone reports almost every
        // vertical video as horizontal.
        let oriented = naturalSize.applying(transform)
        let corrected = CGSize(width: abs(oriented.width), height: abs(oriented.height))

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return VideoInspection(
            duration: CMTimeGetSeconds(duration),
            naturalSize: corrected,
            sizeBytes: values?.fileSize ?? 0
        )
    }

    /// Exports to H.264/AAC at ≤1080×1920, optionally trimmed. Uploading a
    /// 200 MB original over cellular isn't acceptable and R2 egress isn't
    /// free (§4.4), so this always runs even when no trim is applied.
    static func export(
        url: URL,
        trimStart: Double?,
        trimEnd: Double?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard
            let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080)
        else {
            throw VideoExportError.exportFailed("This device can't export that video.")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        if let trimStart, let trimEnd, trimEnd > trimStart {
            let scale = CMTimeScale(600)
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: scale),
                end: CMTime(seconds: trimEnd, preferredTimescale: scale)
            )
        }

        // `AVAssetExportSession.progress` isn't KVO-observable, so it has to
        // be polled. Cancelled by the `defer` once the export completes.
        let poller = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { poller.cancel() }

        // `exportAsynchronously` rather than the async `export()`: the latter
        // is iOS 18+, and this project targets 17. Wrapped in a continuation
        // so callers still get a plain `await`.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            progress(1)
            return output
        case .cancelled:
            throw VideoExportError.exportFailed("Export was cancelled.")
        default:
            throw VideoExportError.exportFailed(session.error?.localizedDescription ?? "Export failed.")
        }
    }

    /// A still at `seconds`, for the creator to scrub and pick a cover frame.
    static func thumbnail(url: URL, at seconds: Double) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        return UIImage(cgImage: cgImage)
    }

    static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    static func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
