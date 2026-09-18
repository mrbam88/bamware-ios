#if os(iOS) && canImport(AuthenticationServices)
import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Sign in with Apple via `ASAuthorizationController` (bamware-ios#4).
///
/// iOS-only — the native Apple ID presentation flow anchors to a
/// `UIWindow`, which this package's macOS 14 target doesn't have in the
/// shape this needs. Guarded with `#if os(iOS) && canImport(AuthenticationServices)`
/// so the macOS host still builds; it just never links this type. (Both
/// this package's own `swift build --target BamwareAccounts` gate and its
/// tests run on the macOS host, so this file's actual iOS body is
/// compile-verified only against an iOS SDK outside that gate — see the
/// PR description. A real device/simulator Apple ID flow cannot run in
/// this environment at all — **unverified**.)
@MainActor
public final class AppleSignInCoordinator: NSObject, SocialSignInCoordinating {
    public let provider: SocialProvider = .apple

    /// One in-flight request's continuation. `ASAuthorizationController`
    /// delegate callbacks land on the main thread; this type is itself
    /// `@MainActor`, so no extra synchronization is needed.
    private var continuation: CheckedContinuation<SocialSignInOutcome, Never>?

    public override init() {
        super.init()
    }

    public func signIn() async -> SocialSignInOutcome {
        let rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple's recommended replay-protection pattern: send the SHA256 of
        // a random nonce here; the identity token echoes it back in its own
        // `nonce` claim. bamware-auth-service doesn't verify that claim yet
        // (`socialAuthService.ts`'s `verifySocialIdToken` checks
        // iss/aud/sub/email only) — this is still the client-side half of
        // the pattern, so server-side verification can be added later with
        // no client change.
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "Unable to generate a secure nonce")
            for byte in randomBytes where result.count < length {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            continuation?.resume(returning: .unavailable(message: "Apple didn't return a usable credential. Try again."))
            return
        }
        // Apple only shares `fullName` on the FIRST authorization for this
        // Apple ID + app; every sign-in after that has nil components here
        // (`SocialCredential.name` doc has the server-side fallback).
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        continuation?.resume(returning: .credential(
            SocialCredential(idToken: idToken, name: name.isEmpty ? nil : name)
        ))
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { continuation = nil }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(returning: .cancelled)
            return
        }
        continuation?.resume(returning: .unavailable(message: "Sign in with Apple failed. Try again."))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
#endif
