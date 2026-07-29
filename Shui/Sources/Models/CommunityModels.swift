import Foundation
import SwiftData

/// Local mirror of a comment on a video (`videos/{videoId}/comments/{id}`).
///
/// Firestore is the source of truth. This exists only so the comment sheet can
/// render instantly from cache and so a comment composed offline survives until
/// it can be posted. Never treat a row here as authoritative.
@Model
final class LessonComment {
    var id: UUID = UUID()
    /// Server document id once posted; nil while the comment is still local-only.
    var remoteID: String?
    var videoID: String = ""
    var authorName: String = ""
    var text: String = ""
    var timestamp: Date = Date()
    var parentRemoteID: String?
    /// Set while this comment is queued for upload and not yet acknowledged.
    var isPendingUpload: Bool = false

    init(
        videoID: String,
        authorName: String,
        text: String,
        parentRemoteID: String? = nil,
        remoteID: String? = nil,
        isPendingUpload: Bool = false
    ) {
        self.id = UUID()
        self.remoteID = remoteID
        self.videoID = videoID
        self.authorName = authorName
        self.text = text
        self.timestamp = Date()
        self.parentRemoteID = parentRemoteID
        self.isPendingUpload = isPendingUpload
    }
}

/// Local mirror of one AI tutor message
/// (`videos/{videoId}/aiThreads/{uid}/messages/{id}`).
///
/// Same contract as `LessonComment`: a cache for instant thread rendering, not
/// the source of truth. The server owns the thread.
@Model
final class TutorChatMessage {
    var id: UUID = UUID()
    var remoteID: String?
    var videoID: String = ""
    var isUser: Bool = false
    var text: String = ""
    var timestamp: Date = Date()
    /// "discuss" or "quizMe" — which tutor mode produced this message.
    var mode: String = "discuss"

    init(
        videoID: String,
        isUser: Bool,
        text: String,
        mode: String = "discuss",
        remoteID: String? = nil
    ) {
        self.id = UUID()
        self.remoteID = remoteID
        self.videoID = videoID
        self.isUser = isUser
        self.text = text
        self.timestamp = Date()
        self.mode = mode
    }
}
