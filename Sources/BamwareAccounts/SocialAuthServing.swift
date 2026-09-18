import Foundation

/// Errors from `SocialAuthServing.socialSignIn`, matching
/// bamware-auth-service's `POST /auth/social` responses
/// (`authHandler.ts`/`socialAuthService.ts`) with copy appropriate to a
/// provider sign-in flow (no email/password involved, unlike
/// `AuthAPIError`).
public enum SocialAuthError: Error, Equatable, LocalizedError {
    /// 401 `Invalid or expired ID token` — the provider token didn't verify
    /// (bad signature, expired, wrong issuer/audience).
    case invalidToken
    /// 401 `UNVERIFIED_PROVIDER_EMAIL` — the provider hasn't verified the
    /// account's email; the server won't link or create off it.
    case unverifiedEmail
    /// 403 `provider_not_allowed` — this tenant hasn't enabled the
    /// provider. Distinct from a coordinator reporting `.unavailable`
    /// client-side; this is the server disagreeing after the fact.
    case providerNotAllowed
    /// 503, message ends in "sign-in is not configured" — the provider's
    /// client ids aren't provisioned in this environment yet.
    case providerNotConfigured(message: String)
    /// 400 `unknown_tenant` or any other validation failure.
    case validation
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidToken: "That sign-in didn't verify. Try again."
        case .unverifiedEmail: "That account's email isn't verified with the provider yet."
        case .providerNotAllowed: "That sign-in option isn't available."
        case .providerNotConfigured(let message): message
        case .validation: "Couldn't complete that sign-in. Try again."
        case .invalidResponse: "Unexpected response from the account service."
        case .http(let statusCode): "Account service error (HTTP \(statusCode))."
        }
    }
}

/// The `POST /auth/social` seam (bamware-ios#4). `AuthAPI` conforms via
/// `AuthAPI+SocialSignIn.swift` — a separate protocol (rather than adding
/// this to `AccountAuthServing`) because `AuthAPI.swift` itself is out of
/// scope for this ticket (bamware-ios#3 owns it).
public protocol SocialAuthServing: Sendable {
    /// - Parameters:
    ///   - tenantId: the auth-service tenant partition (matches
    ///     `SocialLoginSchema.tenantId`).
    ///   - name: forwarded only on first sign-in per provider convention —
    ///     see `SocialCredential`. `nil` omits the field entirely so the
    ///     server's own fallback (token `name` claim, then email local
    ///     part) applies.
    func socialSignIn(
        provider: SocialProvider,
        idToken: String,
        tenantId: String,
        name: String?
    ) async throws -> AuthSession
}
