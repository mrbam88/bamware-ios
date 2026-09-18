import Foundation

/// What a successful native sign-in flow hands back: the provider identity
/// token bamware-auth-service verifies server-side
/// (`socialAuthService.verifySocialIdToken`), plus whatever display name the
/// provider shared.
///
/// Apple only shares the name on the FIRST authorization for a given Apple
/// ID + app combination (every sign-in after that has `name == nil`); Google
/// shares it on every sign-in. Either way `name` is forwarded as-is —
/// `AuthAPI.socialSignIn` sends it only when non-nil, and the server falls
/// back to the token's own `name` claim (Google) or the email local part
/// when it's absent (`socialAuthService.ts`, `socialLogin`).
public struct SocialCredential: Sendable, Equatable {
    public let idToken: String
    public let name: String?

    public init(idToken: String, name: String? = nil) {
        self.idToken = idToken
        self.name = name
    }
}

/// Outcome of one native sign-in attempt.
public enum SocialSignInOutcome: Sendable, Equatable {
    /// A token was acquired — hand it to `AuthAPI.socialSignIn`.
    case credential(SocialCredential)
    /// The user dismissed the native sheet. Callers treat this as a silent
    /// no-op — never an error state (mirrors Baat's RN
    /// `getSocialCredential`, which resolves `null` on cancel;
    /// `src/lib/socialAuth.ts`).
    case cancelled
    /// The flow can't start at all — module unavailable, or this provider
    /// isn't configured for the current tenant (e.g. no Google client id).
    /// `message` is safe to show the user as-is.
    case unavailable(message: String)
}

/// Seam for a single provider's native sign-in flow.
///
/// Two conformers ship across the platform: `AppleSignInCoordinator` (this
/// package, iOS-only) and `GoogleSignInCoordinator` (the separate
/// `BamwareAccountsGoogle` product, bamware-ios#4) — apps that don't offer
/// Google never link the latter's SDK dependency.
public protocol SocialSignInCoordinating: Sendable {
    var provider: SocialProvider { get }
    func signIn() async -> SocialSignInOutcome
}
