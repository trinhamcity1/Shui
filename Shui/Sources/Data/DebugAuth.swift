#if DEBUG
import FirebaseAuth

/// A minimal sign-in shim so the Phase 1 debug upload screen
/// (`Sources/Views/Debug/DebugUploadPipelineView.swift`) can authenticate as
/// a creator/admin before calling creator-only callables. Phase 3 replaces
/// this with a real auth repository; until then this keeps the one Auth call
/// a debug-only screen needs inside `Sources/Data/`, alongside everything
/// else — `import Firebase*` outside this directory still doesn't happen,
/// and none of this compiles into a release build either way.
enum DebugAuth {
    static func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    /// Phase 1 has no signup screen yet — this exists purely so the debug
    /// screen has a way to get *some* account to test against without a
    /// side trip to the Firebase console. A fresh account is role "learner"
    /// (the onUserCreated trigger's default); it still needs
    /// bootstrap-admin.ts before creator-only callables will accept it.
    static func createAccount(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }
}
#endif
