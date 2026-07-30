import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol UserRepository {
    func currentUser() async throws -> UserAccount?
    func updateProfile(displayName: String?, bio: String?, interests: [String]?) async throws
    func claimHandle(_ handle: String) async throws
}

struct FirestoreUserRepository: UserRepository {
    private let db: Firestore
    private let functions: Functions
    private let auth: Auth

    init(
        db: Firestore = FirebaseBootstrap.firestore,
        functions: Functions = FirebaseBootstrap.functions,
        auth: Auth = FirebaseBootstrap.auth
    ) {
        self.db = db
        self.functions = functions
        self.auth = auth
    }

    func currentUser() async throws -> UserAccount? {
        guard let uid = auth.currentUser?.uid else { return nil }
        return try await db.collection("users").document(uid).getDocument().decodedIfExists()
    }

    /// `role`, streaks, totals, and `handle` are Function-only — this only
    /// ever writes the plain profile fields rules allow an owner to touch.
    func updateProfile(displayName: String?, bio: String?, interests: [String]?) async throws {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        var update: [String: Any] = [:]
        if let displayName { update["displayName"] = displayName }
        if let bio { update["bio"] = bio }
        if let interests { update["interests"] = interests }
        guard !update.isEmpty else { return }
        try await db.collection("users").document(uid).updateData(update)
    }

    func claimHandle(_ handle: String) async throws {
        _ = try await functions.httpsCallable("claimHandle").call(["handle": handle])
    }
}

final class InMemoryUserRepository: UserRepository {
    var account: UserAccount?

    init(account: UserAccount? = nil) {
        self.account = account
    }

    func currentUser() async throws -> UserAccount? {
        account
    }

    func updateProfile(displayName: String?, bio: String?, interests: [String]?) async throws {
        guard var account else { return }
        if let displayName { account.displayName = displayName }
        if let bio { account.bio = bio }
        if let interests { account.interests = interests }
        self.account = account
    }

    func claimHandle(_ handle: String) async throws {
        account?.handle = handle
    }
}
