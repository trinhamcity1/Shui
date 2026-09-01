import FirebaseFunctions
import Foundation

/// Developer-API key management (phase-07 §8) — self-serve, no tier gate.
protocol ApiKeyRepository {
    /// The raw key is only ever present in *this* call's return value —
    /// nothing else in the app, then or later, can retrieve it again.
    func createKey(label: String) async throws -> (keyId: String, rawKey: String)
    func listKeys() async throws -> [ApiKeyInfo]
    func revokeKey(keyId: String) async throws
}

struct FirestoreApiKeyRepository: ApiKeyRepository {
    private let functions: Functions

    init(functions: Functions = FirebaseBootstrap.functions) {
        self.functions = functions
    }

    func createKey(label: String) async throws -> (keyId: String, rawKey: String) {
        let result = try await functions.httpsCallable("createApiKey").call(["label": label])
        guard let data = result.data as? [String: Any],
              let keyId = data["keyId"] as? String,
              let rawKey = data["rawKey"] as? String else {
            throw RepositoryError.malformedResponse
        }
        return (keyId, rawKey)
    }

    func listKeys() async throws -> [ApiKeyInfo] {
        let result = try await functions.httpsCallable("listApiKeys").call([:])
        guard let data = result.data as? [String: Any], let rawKeys = data["keys"] else {
            throw RepositoryError.malformedResponse
        }
        guard JSONSerialization.isValidJSONObject(["keys": rawKeys]) else {
            throw RepositoryError.malformedResponse
        }
        let payload = try JSONSerialization.data(withJSONObject: ["keys": rawKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.iso8601WithFractionalSeconds.date(from: string) { return date }
            if let date = Self.iso8601.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return try decoder.decode(ApiKeyListResponse.self, from: payload).keys
    }

    func revokeKey(keyId: String) async throws {
        _ = try await functions.httpsCallable("revokeApiKey").call(["keyId": keyId])
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()
    private static let iso8601 = ISO8601DateFormatter()
}

private struct ApiKeyListResponse: Decodable {
    let keys: [ApiKeyInfo]
}

final class InMemoryApiKeyRepository: ApiKeyRepository {
    var keys: [ApiKeyInfo] = []

    func createKey(label: String) async throws -> (keyId: String, rawKey: String) {
        let keyId = UUID().uuidString
        keys.insert(
            ApiKeyInfo(keyId: keyId, label: label, createdAt: Date(), lastUsedAt: nil, revoked: false, requestCount: 0),
            at: 0
        )
        return (keyId, "shui_live_preview_\(keyId.prefix(8))")
    }

    func listKeys() async throws -> [ApiKeyInfo] {
        keys
    }

    func revokeKey(keyId: String) async throws {
        guard let index = keys.firstIndex(where: { $0.keyId == keyId }) else { return }
        keys[index].revoked = true
    }
}
