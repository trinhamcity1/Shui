import CryptoKit
import Foundation

/// The nonce SwiftUI's `SignInWithAppleButton` needs on its request, and
/// Firebase needs again (hashed) when turning the resulting identity token
/// into a credential — generated once per attempt so the two can be matched
/// up. A pure utility, not tied to `AuthenticationServices` or Firebase
/// itself, since `SignInWithAppleButton` already handles the actual
/// authorization request/response — there's nothing here for a delegate
/// bridge to do.
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate a secure nonce: OSStatus \(status)")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
