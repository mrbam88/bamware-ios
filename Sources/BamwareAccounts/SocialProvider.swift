import Foundation

/// A third-party identity provider `BamwareAccounts` can exchange for a
/// Bamware session via `POST /auth/social` (bamware-ios#4).
///
/// Raw values match bamware-auth-service's `SocialLoginSchema.provider`
/// (`z.enum(['google', 'apple'])`, `src/schemas/authSchemas.ts`) exactly, so
/// `AuthAPI.socialSignIn` can send `provider.rawValue` straight into the
/// request body.
public enum SocialProvider: String, Sendable, Equatable, CaseIterable, Codable {
    case apple
    case google
}
