import Foundation

/// Async client for bamware-auth-service. Compile-time-free base URL and
/// tenant id (both come from `AccountTenantConfig` — apps decide debug vs.
/// release vs. staging hosts; this package never branches on `#if DEBUG`),
/// fail-fast session, typed errors.
///
/// Endpoint contract (auth-service `src/handlers/authHandler.ts`):
/// - `POST /auth/register` `{email, password, name, tenantId}` → 201
///   `{tokens: {accessToken, refreshToken}, user}`; 409 email taken.
/// - `POST /auth/login` `{email, password, tenantId}` → 200 same envelope;
///   401 invalid credentials.
/// - `DELETE /auth/account` (Bearer) → 200 `{ok:true}`; idempotent — a 404
///   means "already gone" and is treated as success client-side, so the
///   deletion flow is safe to re-run after a partial failure (ordered
///   account deletion, see `AccountModel.deleteAccount`).
/// - `POST /auth/refresh` `{refreshToken}` → 200 same envelope, rotated: a
///   NEW access + refresh pair, and the presented refresh token is revoked
///   (single use). 401 on reuse (`refresh_reused`) or any other invalid
///   refresh token — see `SessionRefresher`, which treats any 401 here as
///   "session ended" without needing to distinguish the specific reason
///   (auth-service A2 contract, bamware-auth-service#10).
public struct AuthAPI: AccountAuthServing, Sendable {
    public let baseURL: URL
    private let tenantId: String
    private let session: URLSession

    public init(config: AccountTenantConfig, session: URLSession = .shared) {
        self.baseURL = config.authBaseURL
        self.tenantId = config.tenantId
        self.session = session
    }

    // MARK: - AccountAuthServing

    public func register(email: String, password: String, name: String) async throws -> AuthSession {
        let body = RegisterBody(email: email, password: password, name: name, tenantId: tenantId)
        return try await post("/auth/register", body: body) { status in
            switch status {
            case 409: AuthAPIError.emailAlreadyRegistered
            case 400: AuthAPIError.validation
            default: AuthAPIError.http(statusCode: status)
            }
        }
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let body = LoginBody(email: email, password: password, tenantId: tenantId)
        return try await post("/auth/login", body: body) { status in
            switch status {
            case 401: AuthAPIError.invalidCredentials
            case 400: AuthAPIError.validation
            default: AuthAPIError.http(statusCode: status)
            }
        }
    }

    /// `POST /auth/refresh`. See `SessionRefresher`, which is the intended
    /// caller — it single-flights concurrent refreshes and rotates the
    /// stored pair on success.
    /// The server replies `{tokens: {accessToken, refreshToken}}` with no
    /// `user` (bamware-auth-service PR #15), so the session is rebuilt from
    /// the caller's current user.
    public func refresh(refreshToken: String, user: AuthUser) async throws -> AuthSession {
        let body = RefreshBody(refreshToken: refreshToken)
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AuthAPIError.http(statusCode: http.statusCode) }
        do {
            let envelope = try JSONDecoder().decode(TokensEnvelope.self, from: data)
            return AuthSession(
                accessToken: envelope.tokens.accessToken,
                refreshToken: envelope.tokens.refreshToken,
                user: user
            )
        } catch {
            throw AuthAPIError.invalidResponse
        }
    }

    /// Refresh envelope: tokens only.
    private struct TokensEnvelope: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let tokens: Tokens
    }

    public func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 404: return // already gone — idempotent success
        case 401: throw AuthAPIError.invalidCredentials
        default: throw AuthAPIError.http(statusCode: http.statusCode)
        }
    }

    // MARK: - Plumbing

    private struct RegisterBody: Encodable {
        let email, password, name, tenantId: String
    }

    private struct LoginBody: Encodable {
        let email, password, tenantId: String
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String
    }

    /// The login/register response envelope. `user` decodes the subset apps
    /// need (see `AuthUser`).
    private struct SessionEnvelope: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let tokens: Tokens
        let user: AuthUser
    }

    private func post(
        _ path: String,
        body: some Encodable,
        errorForStatus: (Int) -> AuthAPIError
    ) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw errorForStatus(http.statusCode) }
        do {
            let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
            return AuthSession(
                accessToken: envelope.tokens.accessToken,
                refreshToken: envelope.tokens.refreshToken,
                user: envelope.user
            )
        } catch {
            throw AuthAPIError.invalidResponse
        }
    }
}
