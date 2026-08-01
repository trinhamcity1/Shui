import AuthenticationServices
import CryptoKit
import UIKit

/// Bridges `ASAuthorizationController`'s delegate-based API into
/// async/await, and generates the nonce Sign in with Apple + Firebase's
/// credential-linking flow require to prevent replay attacks. Produces raw
/// Apple credentials only — turning them into a Firebase `AuthCredential` and
/// actually signing in is `AuthRepository`'s job, so this stays a thin,
/// framework-specific bridge.
final class AppleSignInCoordinator: NSObject {
    struct SignInResult {
        let identityToken: String
        let rawNonce: String
        let fullName: PersonNameComponents?
    }

    private var continuation: CheckedContinuation<SignInResult, Error>?
    private var currentNonce: String?

    func signIn() async throws -> SignInResult {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate a secure nonce: OSStatus \(status)")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            continuation?.resume(throwing: RepositoryError.malformedResponse)
            continuation = nil
            return
        }
        continuation?.resume(returning: SignInResult(identityToken: identityToken, rawNonce: nonce, fullName: credential.fullName))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
