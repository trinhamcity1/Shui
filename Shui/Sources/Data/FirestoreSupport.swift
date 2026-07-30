import FirebaseFirestore
import Foundation

/// Shared defensive-decoding helpers for the repository layer. An individual
/// malformed document (an enum value a newer server wrote that this build
/// doesn't know about yet, a field an older client hasn't backfilled) drops
/// out of the page instead of failing the whole collection fetch — the feed
/// keeps scrolling instead of crashing.
extension QuerySnapshot {
    func decoded<T: Decodable>(as type: T.Type = T.self) -> [T] {
        documents.compactMap { try? $0.data(as: T.self) }
    }
}

extension DocumentSnapshot {
    func decodedIfExists<T: Decodable>(as type: T.Type = T.self) -> T? {
        guard exists else { return nil }
        return try? data(as: T.self)
    }
}

/// A single page of a cursor-paginated query. `cursor` is the last document
/// in the page — pass it to the next call's `after:` parameter. `nil` means
/// start from the top (or, on a returned page, that nothing more may follow;
/// callers should also check whether `items.count` came back short of the
/// requested limit).
struct Page<T> {
    var items: [T]
    var cursor: DocumentSnapshot?
}

/// Firestore's `[String: Any]` write payloads need `NSNull()`, not Swift
/// `nil`, to explicitly write or clear an absent optional field.
func firestoreValue(_ value: Any?) -> Any {
    value ?? NSNull()
}

enum RepositoryError: Error {
    case notSignedIn
    case malformedResponse
    case uploadFailed
    case notImplemented
}
