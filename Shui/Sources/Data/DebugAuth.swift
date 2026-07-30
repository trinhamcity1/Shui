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
}
#endif
