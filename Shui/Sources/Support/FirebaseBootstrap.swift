import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// The single place Firebase is configured, and the single place outside
/// `Sources/Data/` that imports it.
///
/// Everything else reaches Firebase through the repository layer. That rule is
/// enforced by a grep in the phase checklist, not by convention alone:
/// `git grep "import Firebase"` outside `Sources/Data/` and this file must
/// return nothing.
enum FirebaseBootstrap {
    private static var isConfigured = false

    /// Configures Firebase and enables Firestore local persistence. Safe to
    /// call more than once; only the first call does anything.
    static func configure() {
        guard !isConfigured else { return }

        FirebaseApp.configure()

        // Persistent local cache, unlimited size. `isPersistenceEnabled` is the
        // older spelling of this and is deprecated on the 11.x SDK.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: FirestoreCacheSizeUnlimited as NSNumber
        )
        Firestore.firestore().settings = settings

        isConfigured = true

        // Deliberately explicit rather than relying on Firebase's own console
        // output, which varies by SDK version. FirebaseApp.app() returning the
        // configured instance — as opposed to nil — is the actual signal that
        // GoogleService-Info.plist was found and parsed; printing its
        // projectID confirms it's this project, not a stale or mismatched one.
        if let app = FirebaseApp.app() {
            print("✅ FirebaseBootstrap: configured project '\(app.options.projectID ?? "?")', bundle '\(app.options.bundleID)'")
        } else {
            print("❌ FirebaseBootstrap: FirebaseApp.configure() ran but FirebaseApp.app() is nil — GoogleService-Info.plist is likely missing from the target's Copy Bundle Resources.")
        }
    }

    // MARK: - Accessors

    static var firestore: Firestore { Firestore.firestore() }
    static var auth: Auth { Auth.auth() }
    static var functions: Functions { Functions.functions(region: "us-central1") }

    /// Points the SDKs at the local emulator suite. Call from a debug-only
    /// launch path before any Firestore use; see the README for the flag.
    #if DEBUG
    static func useEmulators(host: String = "127.0.0.1") {
        // In-memory cache against the emulator: a persistent cache would
        // survive emulator resets and serve stale documents.
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings

        firestore.useEmulator(withHost: host, port: 8080)
        auth.useEmulator(withHost: host, port: 9099)
        functions.useEmulator(withHost: host, port: 5001)
    }
    #endif
}
