import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

protocol UserRepository {
    func currentUser() async throws -> UserAccount?
    /// Creates `users/{uid}` for the currently signed-in Firebase Auth user
    /// if it doesn't exist yet — the client-side half of account creation;
    /// `onUserCreated` (a Firestore trigger) sets the trusted `role` custom
    /// claim once this write lands. A no-op if the document already exists,
    /// so it's safe to call after every sign-in, not just the first.
    func createProfileIfNeeded(displayName: String, photoURL: String?, authProviders: [String], isGuest: Bool) async throws
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

    /// `handle` starts empty rather than derived from anything guessable —
    /// `claimHandle` is what actually reserves one, prompted for right after
    /// this on a real first sign-in (Apple/email). Every field rules require
    /// at create time is written explicitly; nothing here is optional on the
    /// Swift model, so a partial write would fail to decode later.
    func createProfileIfNeeded(displayName: String, photoURL: String?, authProviders: [String], isGuest: Bool) async throws {
        guard let uid = auth.currentUser?.uid else { throw RepositoryError.notSignedIn }
        let ref = db.collection("users").document(uid)
        guard try await ref.getDocument().exists == false else { return }
        try await ref.setData([
            "displayName": displayName,
            "handle": "",
            "photoURL": firestoreValue(photoURL),
            "bio": NSNull(),
            "role": UserAccount.Role.learner.rawValue,
            "authProviders": authProviders,
            "interests": [],
            "createdAt": FieldValue.serverTimestamp(),
            "lastActiveAt": FieldValue.serverTimestamp(),
            "currentStreak": 0,
            "longestStreak": 0,
            "totalVideosCompleted": 0,
            "totalQuizzesPassed": 0,
            "isGuest": isGuest,
            "isDeleted": false,
        ])
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

    func createProfileIfNeeded(displayName: String, photoURL: String?, authProviders: [String], isGuest: Bool) async throws {
        guard account == nil else { return }
        account = UserAccount(
            id: "preview-user",
            displayName: displayName,
            handle: "",
            photoURL: photoURL,
            bio: nil,
            role: .learner,
            authProviders: authProviders,
            interests: [],
            createdAt: Date(),
            lastActiveAt: Date(),
            currentStreak: 0,
            longestStreak: 0,
            totalVideosCompleted: 0,
            totalQuizzesPassed: 0,
            isGuest: isGuest,
            isDeleted: false
        )
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
