import Foundation

// Shared account platform (ADR 0001, bamware-ai/docs/bamware-account-platform.md).
//
// Accounts are OPTIONAL for any consuming app: everything works
// anonymously; an account only gates whatever the app decides needs one
// (e.g. community submissions). Auth is served by bamware-auth-service (one
// multi-tenant API, bcrypt + JWT, `tenantId` per app) — see
// `AccountTenantConfig`.

/// The signed-in user, as returned by the auth service. The service sends
/// more keys (role, createdAt, schemaVersion, …); we decode only what apps
/// display so additive server changes never break the client.
public struct AuthUser: Codable, Hashable, Sendable {
    public let userId: String
    public let email: String
    public let name: String
    public let tenantId: String

    public init(userId: String, email: String, name: String, tenantId: String) {
        self.userId = userId
        self.email = email
        self.name = name
        self.tenantId = tenantId
    }
}

/// A signed-in session: the token pair plus the user it belongs to.
/// Access tokens expire in ≤15 min; v1 does not auto-refresh (account
/// actions are rare and re-login is cheap) — the refresh token is stored
/// so refresh can ship without a session-shape migration.
public struct AuthSession: Codable, Hashable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let user: AuthUser

    public init(accessToken: String, refreshToken: String, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

public enum AuthAPIError: Error, Equatable, LocalizedError {
    /// Wrong email/password (or unknown account — the service deliberately
    /// does not distinguish, to prevent account enumeration).
    case invalidCredentials
    /// Register hit an email that already has an account in this tenant.
    case emailAlreadyRegistered
    /// The request failed validation server-side (e.g. password < 8 chars).
    case validation
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid email or password."
        case .emailAlreadyRegistered: "That email already has an account. Try signing in."
        case .validation: "Check your email and password (at least 8 characters) and try again."
        case .invalidResponse: "Unexpected response from the account service."
        case .http(let statusCode): "Account service error (HTTP \(statusCode))."
        }
    }
}

/// Seam for the auth-service client. Live: `AuthAPI`. Deterministic
/// (UI tests / previews): `AuthScenarioService`. Apps resolve which one to
/// use at their composition root.
public protocol AccountAuthServing: Sendable {
    func register(email: String, password: String, name: String) async throws -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    /// Idempotent server-side (404 == already gone == success).
    func deleteAccount(accessToken: String) async throws
}

/// Step 1 of the ordered account deletion (see `AccountModel.deleteAccount`):
/// delete the user's app content BEFORE the auth record, because deleting the
/// auth record kills the very token the content deletion needs.
///
/// Apps that store no server-side user content can use `NoUserContentService`
/// (a documented no-op). Apps that do implement this protocol with their own
/// content-cascade service; the ordering is pinned by `AccountModelTests` so
/// it cannot regress.
public protocol AccountContentDeleting: Sendable {
    func deleteUserContent(accessToken: String) async throws
}

/// No server-side user content to delete — documented no-op (see
/// `AccountContentDeleting`).
public struct NoUserContentService: AccountContentDeleting, Sendable {
    public init() {}
    public func deleteUserContent(accessToken: String) async throws {}
}
