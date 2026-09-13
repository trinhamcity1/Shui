import Foundation

/// Maps a caught `Error` to copy that's safe to show a learner — the
/// difference matters because a bare `error.localizedDescription` can
/// surface raw Firestore/backend text like "Missing or insufficient
/// permissions," which reads as a broken app, not a transient hiccup.
///
/// Matches on the raw NSError domain/code literals rather than importing
/// FirebaseFirestore's typed `FirestoreErrorCode` — this file lives outside
/// `Data/`, and `FirebaseBootstrap.swift` documents that only `Data/` (and
/// itself) may import Firebase directly. "FIRFirestoreErrorDomain" and `7`
/// (gRPC's standard PERMISSION_DENIED status) are stable, publicly
/// documented values, not implementation details likely to shift.
enum UserFacingError {
    private static let firestoreErrorDomain = "FIRFirestoreErrorDomain"
    private static let firestorePermissionDeniedCode = 7

    static func describe(_ error: Error, fallback: String = "Something went wrong. Please try again.") -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach Shui. Check your connection and try again."
        }
        if nsError.domain == firestoreErrorDomain, nsError.code == firestorePermissionDeniedCode {
            return "Couldn't complete that — please try again in a moment."
        }
        return fallback
    }
}
