import Foundation
import UIKit

/// The upload flow's stages. Modeled explicitly rather than as a pile of
/// booleans so the view can only ever render one coherent state, and so a
/// failure knows which step to offer a retry for.
enum UploadStage: Equatable {
    case picking
    case inspecting
    case ready
    case exporting(progress: Double)
    case uploading(fraction: Double, bytesSent: Int64, totalBytes: Int64)
    case finalizing
    case done(videoId: String)
    case failed(message: String, canRetry: Bool)

    var isBusy: Bool {
        switch self {
        case .inspecting, .exporting, .uploading, .finalizing: return true
        default: return false
        }
    }
}

@MainActor
final class VideoUploadViewModel: ObservableObject {
    @Published private(set) var stage: UploadStage = .picking
    @Published private(set) var inspection: VideoInspection?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var exportedSizeBytes: Int = 0
    @Published private(set) var thumbnail: UIImage?

    @Published var title = ""
    @Published var videoDescription = ""
    @Published var transcript = ""
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var thumbnailSeconds: Double = 1

    let topic: Topic
    private let environment: AppEnvironment
    private var sourceURL: URL?
    /// Held so a retry after a presign expiry can re-mint rather than reuse
    /// a dead URL (§4, "presign expiry (re-mint and retry)").
    private var pendingVideoId: String?

    init(topic: Topic, environment: AppEnvironment) {
        self.topic = topic
        self.environment = environment
    }

    var canStartUpload: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && exportedURL != nil
            && !stage.isBusy
    }

    var trimmedDuration: Double { max(0, trimEnd - trimStart) }

    // MARK: - Pick and inspect

    func accept(pickedURL url: URL) async {
        sourceURL = url
        stage = .inspecting
        do {
            let result = try await VideoExporter.inspect(url: url)
            inspection = result
            trimStart = 0
            trimEnd = result.duration
            thumbnailSeconds = min(1, result.duration)
            stage = .ready
            await refreshThumbnail()
        } catch {
            stage = .failed(message: error.localizedDescription, canRetry: false)
        }
    }

    func refreshThumbnail() async {
        guard let sourceURL else { return }
        thumbnail = try? await VideoExporter.thumbnail(url: sourceURL, at: thumbnailSeconds)
    }

    /// Runs the transcode so the creator sees the real compressed size before
    /// committing to an upload (§4.4).
    func prepareForUpload() async {
        guard let sourceURL else { return }
        stage = .exporting(progress: 0)
        do {
            let output = try await VideoExporter.export(
                url: sourceURL,
                trimStart: trimStart > 0 ? trimStart : nil,
                trimEnd: trimEnd < (inspection?.duration ?? 0) ? trimEnd : nil,
                progress: { [weak self] value in
                    Task { @MainActor in
                        guard let self, case .exporting = self.stage else { return }
                        self.stage = .exporting(progress: value)
                    }
                }
            )
            exportedURL = output
            exportedSizeBytes = VideoExporter.fileSize(of: output)
            stage = .ready
        } catch {
            stage = .failed(message: error.localizedDescription, canRetry: true)
        }
    }

    // MARK: - Upload

    func startUpload() async {
        guard let exportedURL, let topicId = topic.id else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            stage = .uploading(fraction: 0, bytesSent: 0, totalBytes: Int64(exportedSizeBytes))
            let ticket = try await environment.uploads.createVideoUpload(
                topicId: topicId,
                title: trimmedTitle,
                description: videoDescription.isEmpty ? nil : videoDescription,
                sizeBytes: exportedSizeBytes,
                durationSeconds: trimmedDuration,
                aspectRatio: inspection?.aspectRatio ?? (9.0 / 16.0),
                contentType: "video/mp4"
            )
            pendingVideoId = ticket.videoId

            try await environment.uploads.uploadFile(
                exportedURL,
                to: ticket.uploadURL,
                contentType: "video/mp4",
                onProgress: { [weak self] sent, total in
                    Task { @MainActor in
                        guard let self, case .uploading = self.stage else { return }
                        let fraction = total > 0 ? Double(sent) / Double(total) : 0
                        self.stage = .uploading(fraction: fraction, bytesSent: sent, totalBytes: total)
                    }
                }
            )

            stage = .finalizing
            var thumbnailKey: String?
            if let thumbnail, let jpeg = thumbnail.jpegData(compressionQuality: 0.8) {
                // A failed thumbnail must not fail the video — R2 already
                // has the video's bytes at this point, and a missing
                // thumbnail is a cosmetic gap the editor can fix later.
                do {
                    let thumbTicket = try await environment.uploads.createThumbnailUpload(
                        videoId: ticket.videoId, sizeBytes: jpeg.count
                    )
                    try await environment.uploads.uploadData(jpeg, to: thumbTicket.uploadURL, contentType: "image/jpeg")
                    thumbnailKey = thumbTicket.r2Key
                } catch {
                    thumbnailKey = nil
                }
            }

            try await environment.uploads.finalize(
                videoId: ticket.videoId,
                thumbnailR2Key: thumbnailKey,
                transcript: transcript.isEmpty ? nil : transcript
            )
            stage = .done(videoId: ticket.videoId)
        } catch {
            stage = .failed(message: Self.describe(error), canRetry: true)
        }
    }

    /// Re-runs the whole upload, re-minting the presigned URL. Deliberately
    /// not a resume of the previous transfer: R2 presigned PUTs aren't
    /// resumable, so pretending otherwise would be a lie in the UI. The
    /// export is reused, which is the expensive part.
    func retryUpload() async {
        guard exportedURL != nil else { return }
        await startUpload()
    }

    /// Cancelling before finalize leaves a `pending` video doc behind. The
    /// Phase 1 cleanup job would eventually mark it failed after 24h, but
    /// removing it now is what the spec asks for (§4.7) and keeps the topic
    /// editor free of ghost rows in the meantime.
    func cancelPendingUpload() async {
        guard let pendingVideoId else { return }
        try? await environment.videos.softDelete(videoId: pendingVideoId)
        self.pendingVideoId = nil
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "The upload was interrupted. Check your connection and try again."
        }
        return error.localizedDescription
    }
}
