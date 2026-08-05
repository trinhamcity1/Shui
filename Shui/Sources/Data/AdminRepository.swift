import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Mirrors `reports/{reportId}`. `targetPath` is a full Firestore document
/// path (`videos/{id}` or `videos/{id}/comments/{id}`) rather than a pair of
/// ids, because the queue has to render — and act on — both kinds of target
/// without branching on shape at every call site.
struct ContentReport: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case open, dismissed, actioned
    }

    @DocumentID var id: String?
    var targetType: String
    var targetPath: String
    var reporterUid: String
    var reason: String
    var note: String?
    var status: Status
    var actionNote: String?
    var actionedBy: String?
    var createdAt: Date?
    var actionedAt: Date?

    /// The video this report ultimately concerns, for both target shapes —
    /// the queue shows the reported comment *in context*, which means
    /// loading its video regardless of which kind of thing was reported.
    var videoId: String? {
        let parts = targetPath.split(separator: "/")
        guard parts.count >= 2, parts[0] == "videos" else { return nil }
        return String(parts[1])
    }

    var commentId: String? {
        let parts = targetPath.split(separator: "/")
        guard parts.count >= 4, parts[2] == "comments" else { return nil }
        return String(parts[3])
    }
}

enum ReportAction: String {
    case dismiss
    case deleteContent
}

/// Admin-only operations. Every method here is additionally gated server-side
/// (`requireRole(["admin"])` or an `isAdmin()` rule) — hiding the screens is
/// a UX decision, never the security boundary.
protocol AdminRepository {
    func openReports(limit: Int) async throws -> [ContentReport]
    func action(reportId: String, action: ReportAction, note: String?) async throws
    func assignRole(uid: String, role: UserAccount.Role) async throws
    func findUser(byHandle handle: String) async throws -> UserAccount?
    func findUser(byEmailPrefix prefix: String) async throws -> [UserAccount]
    func saveCategory(
        categoryId: String?,
        title: String,
        description: String,
        sfSymbol: String,
        accentHex: String,
        sortOrder: Int,
        isActive: Bool
    ) async throws -> String
}

struct FirebaseAdminRepository: AdminRepository {
    private let db: Firestore
    private let functions: Functions

    init(db: Firestore = FirebaseBootstrap.firestore, functions: Functions = FirebaseBootstrap.functions) {
        self.db = db
        self.functions = functions
    }

    func openReports(limit: Int) async throws -> [ContentReport] {
        let snapshot = try await db.collection("reports")
            .whereField("status", isEqualTo: ContentReport.Status.open.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.decoded()
    }

    func action(reportId: String, action: ReportAction, note: String?) async throws {
        var payload: [String: Any] = ["reportId": reportId, "action": action.rawValue]
        if let note, !note.isEmpty { payload["note"] = note }
        _ = try await functions.httpsCallable("actionReport").call(payload)
    }

    func assignRole(uid: String, role: UserAccount.Role) async throws {
        _ = try await functions.httpsCallable("assignRole").call(["uid": uid, "role": role.rawValue])
    }

    /// Handles are unique and stored lowercase (see `claimHandle`), so this
    /// is an exact match rather than a prefix scan.
    func findUser(byHandle handle: String) async throws -> UserAccount? {
        let normalized = handle.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !normalized.isEmpty else { return nil }
        let snapshot = try await db.collection("users")
            .whereField("handle", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments()
        return snapshot.decoded().first
    }

    /// Email isn't stored on `users/{uid}` — it lives in Firebase Auth, which
    /// a client can't query. Falls back to a displayName prefix match so the
    /// admin still has a way to find someone who hasn't set a handle, rather
    /// than pretending to search by email and silently returning nothing.
    func findUser(byEmailPrefix prefix: String) async throws -> [UserAccount] {
        let normalized = prefix.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return [] }
        let snapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: normalized)
            .whereField("displayName", isLessThan: normalized + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        return snapshot.decoded()
    }

    func saveCategory(
        categoryId: String?,
        title: String,
        description: String,
        sfSymbol: String,
        accentHex: String,
        sortOrder: Int,
        isActive: Bool
    ) async throws -> String {
        var payload: [String: Any] = [
            "title": title,
            "description": description,
            "sfSymbol": sfSymbol,
            "accentHex": accentHex,
            "sortOrder": sortOrder,
            "isActive": isActive,
        ]
        if let categoryId { payload["categoryId"] = categoryId }
        let result = try await functions.httpsCallable("saveCategory").call(payload)
        guard let data = result.data as? [String: Any], let id = data["categoryId"] as? String else {
            throw RepositoryError.malformedResponse
        }
        return id
    }
}

final class InMemoryAdminRepository: AdminRepository {
    var reports: [ContentReport]
    var users: [UserAccount]
    var assignedRoles: [(uid: String, role: UserAccount.Role)] = []

    init(reports: [ContentReport] = [], users: [UserAccount] = []) {
        self.reports = reports
        self.users = users
    }

    func openReports(limit: Int) async throws -> [ContentReport] {
        Array(reports.filter { $0.status == .open }.prefix(limit))
    }

    func action(reportId: String, action: ReportAction, note: String?) async throws {
        guard let index = reports.firstIndex(where: { $0.id == reportId }) else { return }
        reports[index].status = action == .dismiss ? .dismissed : .actioned
        reports[index].actionNote = note
    }

    func assignRole(uid: String, role: UserAccount.Role) async throws {
        assignedRoles.append((uid: uid, role: role))
    }

    func findUser(byHandle handle: String) async throws -> UserAccount? {
        users.first { $0.handle == handle.lowercased() }
    }

    func findUser(byEmailPrefix prefix: String) async throws -> [UserAccount] {
        users.filter { $0.displayName.hasPrefix(prefix) }
    }

    func saveCategory(
        categoryId: String?,
        title: String,
        description: String,
        sfSymbol: String,
        accentHex: String,
        sortOrder: Int,
        isActive: Bool
    ) async throws -> String {
        categoryId ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
