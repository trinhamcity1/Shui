import FirebaseAuth
import FirebaseFunctions
import Foundation

enum AuthLinkOutcome {
    /// The credential was linked to the current (guest) account in place —
    /// same uid, so all existing progress carries over automatically.
    case linked(isNewUser: Bool)
    /// Firebase rejected the link because that credential already belongs to
    /// a different, pre-existing account — signed into that account instead.
    /// The uid changed, so anything recorded under the old anonymous uid
    /// does not carry over; the caller is responsible for telling the
    /// learner that explicitly.
    case signedIntoExistingAccount
}

struct AuthUpgradeResult {
    let outcome: AuthLinkOutcome
    /// Best-known display name for a brand-new account — Apple's `fullName`
    /// on a first sign-in (Apple only provides it once, ever), or nil when
    /// there's nothing better to suggest than the account-creation default.
    let suggestedDisplayName: String?
}

protocol AuthRepository {
    var currentUID: String? { get }
    /// True for an anonymous session or no session at all — false only once
    /// a real, recoverable account (Apple or email) is signed in.
    var isGuest: Bool { get }
    var linkedProviderIDs: [String] { get }

    /// Starts (or resumes) a session. A no-op if already signed in, guest or
    /// otherwise — safe to call on every launch.
    func signInAnonymouslyIfNeeded() async throws
    /// The `role` custom claim read from the ID token — the same value
    /// `request.auth.token.role` carries server-side, and the only role
    /// source app code should gate UI on. `users/{uid}.role` is a display
    /// mirror that a client could in principle observe mid-update; this
    /// comes from the signed token itself.
    ///
    /// `forceRefresh` re-mints the token instead of using the cached one,
    /// which is what makes a just-granted `creator` role appear without a
    /// reinstall — claims are baked into the token at mint time, so a
    /// cached token keeps reporting the old role for up to an hour.
    func roleClaim(forceRefresh: Bool) async -> UserAccount.Role
    /// Takes the raw pieces `SignInWithAppleButton`'s completion handler
    /// produces — the view owns the actual Apple authorization request
    /// (that's what draws the real HIG button and prompts Face ID) and this
    /// only ever turns a successful result into a Firebase credential.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUpgradeResult
    /// Handles both sign-up and sign-in with one call, per the phase spec's
    /// "sign-up / sign-in detection": links the credential to the current
    /// guest session first (a genuinely new account), and falls back to a
    /// plain sign-in against the existing account if Firebase reports the
    /// email is already taken.
    func continueWithEmail(email: String, password: String) async throws -> AuthUpgradeResult
    func sendPasswordReset(email: String) async throws
    func signOut() throws
    /// Deletes the account server-side (`deleteAccount` callable), then
    /// clears the local session. Does not start a new guest session —
    /// that's the caller's job, same as at first launch.
    func deleteAccount() async throws
}

final class FirebaseAuthRepository: AuthRepository {
    private let auth: Auth
    private let functions: Functions

    init(auth: Auth = FirebaseBootstrap.auth, functions: Functions = FirebaseBootstrap.functions) {
        self.auth = auth
        self.functions = functions
    }

    var currentUID: String? { auth.currentUser?.uid }

    var isGuest: Bool { auth.currentUser?.isAnonymous ?? true }

    var linkedProviderIDs: [String] {
        auth.currentUser?.providerData.map(\.providerID) ?? []
    }

    func signInAnonymouslyIfNeeded() async throws {
        guard auth.currentUser == nil else { return }
        _ = try await auth.signInAnonymously()
    }

    func roleClaim(forceRefresh: Bool) async -> UserAccount.Role {
        guard let user = auth.currentUser else { return .learner }
        // A failure here means "we couldn't prove elevated access", which is
        // exactly `learner` — never surface it as an error the caller has to
        // interpret, since every interpretation other than "no privileges"
        // would be wrong.
        guard let result = try? await user.getIDTokenResult(forcingRefresh: forceRefresh),
              let raw = result.claims["role"] as? String,
              let role = UserAccount.Role(rawValue: raw)
        else {
            return .learner
        }
        return role
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUpgradeResult {
        let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idToken, rawNonce: rawNonce)
        let suggestedName = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return try await link(credential: credential, suggestedDisplayName: suggestedName.isEmpty ? nil : suggestedName)
    }

    func continueWithEmail(email: String, password: String) async throws -> AuthUpgradeResult {
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            return try await link(credential: credential, suggestedDisplayName: nil)
        } catch let error as NSError where AuthErrorCode(rawValue: error.code) == .emailAlreadyInUse {
            // A real account already owns this email — this is a sign-in,
            // not a sign-up, and the password just entered is what
            // authenticates it (or correctly fails to, if it's wrong).
            _ = try await auth.signIn(withEmail: email, password: password)
            return AuthUpgradeResult(outcome: .signedIntoExistingAccount, suggestedDisplayName: nil)
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        try auth.signOut()
    }

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call([:])
        try auth.signOut()
    }

    /// Links `credential` to the current session (upgrading a guest in
    /// place). If that credential already belongs to a different account,
    /// Firebase surfaces the existing account's own credential in the
    /// error's `userInfo` — signing in with *that* is how the spec's "sign
    /// into it and offer to merge" actually happens; there's no separate
    /// API to fetch it after the fact.
    private func link(credential: AuthCredential, suggestedDisplayName: String?) async throws -> AuthUpgradeResult {
        guard let currentUser = auth.currentUser else {
            let result = try await auth.signIn(with: credential)
            return AuthUpgradeResult(
                outcome: .linked(isNewUser: result.additionalUserInfo?.isNewUser ?? true),
                suggestedDisplayName: suggestedDisplayName
            )
        }
        do {
            let result = try await currentUser.link(with: credential)
            return AuthUpgradeResult(
                outcome: .linked(isNewUser: result.additionalUserInfo?.isNewUser ?? true),
                suggestedDisplayName: suggestedDisplayName
            )
        } catch let error as NSError where AuthErrorCode(rawValue: error.code) == .credentialAlreadyInUse {
            guard let updatedCredential = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential else {
                throw error
            }
            _ = try await auth.signIn(with: updatedCredential)
            return AuthUpgradeResult(outcome: .signedIntoExistingAccount, suggestedDisplayName: nil)
        }
    }
}

final class InMemoryAuthRepository: AuthRepository {
    var currentUID: String? = "preview-user"
    var isGuest = true
    var linkedProviderIDs: [String] = []
    /// Settable so a preview or test can stand up a creator/admin session
    /// without a real token — the whole point of the seam.
    var role: UserAccount.Role = .learner

    func signInAnonymouslyIfNeeded() async throws {
        if currentUID == nil {
            currentUID = "preview-user"
            isGuest = true
        }
    }

    func roleClaim(forceRefresh: Bool) async -> UserAccount.Role { role }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUpgradeResult {
        isGuest = false
        linkedProviderIDs = ["apple.com"]
        return AuthUpgradeResult(outcome: .linked(isNewUser: true), suggestedDisplayName: "Preview Learner")
    }

    func continueWithEmail(email: String, password: String) async throws -> AuthUpgradeResult {
        isGuest = false
        linkedProviderIDs = ["password"]
        return AuthUpgradeResult(outcome: .linked(isNewUser: true), suggestedDisplayName: nil)
    }

    func sendPasswordReset(email: String) async throws {}

    func signOut() throws {
        currentUID = nil
        isGuest = true
        linkedProviderIDs = []
    }

    func deleteAccount() async throws {
        currentUID = nil
        linkedProviderIDs = []
    }
}
