import Foundation

/// The safe projection `listApiKeys` returns (phase-07 §8) — never the raw
/// key or its hash, both of which exist only server-side.
struct ApiKeyInfo: Codable, Identifiable, Hashable {
    var keyId: String
    var label: String
    var createdAt: Date?
    var lastUsedAt: Date?
    var revoked: Bool
    var requestCount: Int

    var id: String { keyId }
}
