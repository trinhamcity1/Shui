import FirebaseFunctions
import Foundation

struct VideoUploadTicket {
    var videoId: String
    var uploadURL: URL
    var r2Key: String
    var playbackURL: String
    var expiresAt: Date
}

struct ThumbnailUploadTicket {
    var uploadURL: URL
    var r2Key: String
    var thumbnailURL: String
    var expiresAt: Date
}

struct TopicCoverUploadTicket {
    var uploadURL: URL
    var r2Key: String
    var coverImageURL: String
    var expiresAt: Date
}

protocol UploadRepository {
    func createVideoUpload(
        topicId: String,
        title: String,
        description: String?,
        sizeBytes: Int,
        durationSeconds: Double,
        aspectRatio: Double,
        contentType: String
    ) async throws -> VideoUploadTicket

    /// PUTs the file straight to the presigned R2 URL — never through
    /// Firebase, which never sees the video bytes.
    func uploadFile(_ fileURL: URL, to uploadURL: URL, contentType: String) async throws

    func finalize(videoId: String, thumbnailR2Key: String?, transcript: String?) async throws

    func createThumbnailUpload(videoId: String, sizeBytes: Int) async throws -> ThumbnailUploadTicket

    func createTopicCoverUpload(topicId: String, sizeBytes: Int) async throws -> TopicCoverUploadTicket

    /// Uploads raw bytes already in memory (a JPEG the picker produced),
    /// rather than a file on disk. Kept separate from `uploadFile` because
    /// cover images and thumbnails are small and never worth writing to a
    /// temp file first — videos are the opposite, and stream from disk.
    func uploadData(_ data: Data, to uploadURL: URL, contentType: String) async throws
}

struct FirebaseUploadRepository: UploadRepository {
    private let functions: Functions
    private let urlSession: URLSession

    init(functions: Functions = FirebaseBootstrap.functions, urlSession: URLSession = .shared) {
        self.functions = functions
        self.urlSession = urlSession
    }

    func createVideoUpload(
        topicId: String,
        title: String,
        description: String?,
        sizeBytes: Int,
        durationSeconds: Double,
        aspectRatio: Double,
        contentType: String
    ) async throws -> VideoUploadTicket {
        var payload: [String: Any] = [
            "topicId": topicId,
            "title": title,
            "sizeBytes": sizeBytes,
            "durationSeconds": durationSeconds,
            "aspectRatio": aspectRatio,
            "contentType": contentType,
        ]
        if let description { payload["description"] = description }

        let result = try await functions.httpsCallable("createVideoUpload").call(payload)
        guard
            let data = result.data as? [String: Any],
            let videoId = data["videoId"] as? String,
            let uploadURLString = data["uploadURL"] as? String,
            let uploadURL = URL(string: uploadURLString),
            let r2Key = data["r2Key"] as? String,
            let playbackURL = data["playbackURL"] as? String,
            let expiresAtMillis = data["expiresAt"] as? Double
        else {
            throw RepositoryError.malformedResponse
        }
        return VideoUploadTicket(
            videoId: videoId,
            uploadURL: uploadURL,
            r2Key: r2Key,
            playbackURL: playbackURL,
            expiresAt: Date(timeIntervalSince1970: expiresAtMillis / 1000)
        )
    }

    func uploadFile(_ fileURL: URL, to uploadURL: URL, contentType: String) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await urlSession.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RepositoryError.uploadFailed
        }
    }

    func finalize(videoId: String, thumbnailR2Key: String?, transcript: String?) async throws {
        var payload: [String: Any] = ["videoId": videoId]
        if let thumbnailR2Key { payload["thumbnailR2Key"] = thumbnailR2Key }
        if let transcript { payload["transcript"] = transcript }
        _ = try await functions.httpsCallable("finalizeVideoUpload").call(payload)
    }

    func createThumbnailUpload(videoId: String, sizeBytes: Int) async throws -> ThumbnailUploadTicket {
        let result = try await functions.httpsCallable("createThumbnailUpload").call([
            "videoId": videoId,
            "contentType": "image/jpeg",
            "sizeBytes": sizeBytes,
        ])
        guard
            let data = result.data as? [String: Any],
            let uploadURLString = data["uploadURL"] as? String,
            let uploadURL = URL(string: uploadURLString),
            let r2Key = data["r2Key"] as? String,
            let thumbnailURL = data["thumbnailURL"] as? String,
            let expiresAtMillis = data["expiresAt"] as? Double
        else {
            throw RepositoryError.malformedResponse
        }
        return ThumbnailUploadTicket(
            uploadURL: uploadURL,
            r2Key: r2Key,
            thumbnailURL: thumbnailURL,
            expiresAt: Date(timeIntervalSince1970: expiresAtMillis / 1000)
        )
    }

    func createTopicCoverUpload(topicId: String, sizeBytes: Int) async throws -> TopicCoverUploadTicket {
        let result = try await functions.httpsCallable("createTopicCoverUpload").call([
            "topicId": topicId,
            "contentType": "image/jpeg",
            "sizeBytes": sizeBytes,
        ])
        guard
            let data = result.data as? [String: Any],
            let uploadURLString = data["uploadURL"] as? String,
            let uploadURL = URL(string: uploadURLString),
            let r2Key = data["r2Key"] as? String,
            let coverImageURL = data["coverImageURL"] as? String,
            let expiresAtMillis = data["expiresAt"] as? Double
        else {
            throw RepositoryError.malformedResponse
        }
        return TopicCoverUploadTicket(
            uploadURL: uploadURL,
            r2Key: r2Key,
            coverImageURL: coverImageURL,
            expiresAt: Date(timeIntervalSince1970: expiresAtMillis / 1000)
        )
    }

    func uploadData(_ data: Data, to uploadURL: URL, contentType: String) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await urlSession.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RepositoryError.uploadFailed
        }
    }
}

final class InMemoryUploadRepository: UploadRepository {
    func createVideoUpload(
        topicId: String,
        title: String,
        description: String?,
        sizeBytes: Int,
        durationSeconds: Double,
        aspectRatio: Double,
        contentType: String
    ) async throws -> VideoUploadTicket {
        VideoUploadTicket(
            videoId: UUID().uuidString,
            uploadURL: URL(string: "https://example.com/upload")!,
            r2Key: "videos/preview.mp4",
            playbackURL: "https://example.com/preview.mp4",
            expiresAt: Date().addingTimeInterval(1800)
        )
    }

    func uploadFile(_ fileURL: URL, to uploadURL: URL, contentType: String) async throws {}

    func finalize(videoId: String, thumbnailR2Key: String?, transcript: String?) async throws {}

    func createThumbnailUpload(videoId: String, sizeBytes: Int) async throws -> ThumbnailUploadTicket {
        ThumbnailUploadTicket(
            uploadURL: URL(string: "https://example.com/upload")!,
            r2Key: "thumbs/preview.jpg",
            thumbnailURL: "https://example.com/preview.jpg",
            expiresAt: Date().addingTimeInterval(1800)
        )
    }

    func createTopicCoverUpload(topicId: String, sizeBytes: Int) async throws -> TopicCoverUploadTicket {
        TopicCoverUploadTicket(
            uploadURL: URL(string: "https://example.com/upload")!,
            r2Key: "covers/preview.jpg",
            coverImageURL: "https://example.com/cover.jpg",
            expiresAt: Date().addingTimeInterval(1800)
        )
    }

    func uploadData(_ data: Data, to uploadURL: URL, contentType: String) async throws {}
}
