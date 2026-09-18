import Foundation

/// `AuthAPI` conformance to `SocialAuthServing` (bamware-ios#4).
///
/// A NEW file rather than a change to `AuthAPI.swift` — that file is out of
/// scope for this ticket (bamware-ios#3 owns it). Because of that, this
/// extension cannot reach `AuthAPI`'s `private` `tenantId`/`session`
/// storage (Swift `private` is file-scoped, so a same-type extension in a
/// different file has no access) or its `private` `post` helper/
/// `SessionEnvelope` type. So this reimplements the small bit of request/
/// response plumbing those already do privately, using only `AuthAPI`'s
/// `public` `baseURL`, plus a `tenantId`/`session` supplied by the caller —
/// the same values the app already passed into `AuthAPI(config:session:)`
/// to build this instance (see `AccountModel.SocialSignInSupport`, which
/// carries both alongside the `AuthAPI` it wraps).
///
/// Endpoint contract (`bamware-auth-service` `src/handlers/authHandler.ts`,
/// `src/schemas/authSchemas.ts` `SocialLoginSchema`):
/// `POST /auth/social` `{provider, idToken, tenantId, name?}` → 200 same
/// envelope as register/login (`{tokens: {accessToken, refreshToken}, user}`);
/// 401 invalid/expired token or unverified provider email; 403 tenant
/// hasn't enabled this provider; 503 provider not configured in this
/// environment; 400 unknown tenant / validation.
extension AuthAPI: SocialAuthServing {
    /// Protocol-satisfying overload — always uses `URLSession.shared`,
    /// since `AuthAPI`'s own injected session is unreachable (see above).
    /// Use the `session:` overload directly (not through
    /// `SocialAuthServing`) when a caller — e.g. a test — needs to
    /// intercept the request.
    public func socialSignIn(
        provider: SocialProvider,
        idToken: String,
        tenantId: String,
        name: String?
    ) async throws -> AuthSession {
        try await socialSignIn(
            provider: provider, idToken: idToken, tenantId: tenantId, name: name, session: .shared
        )
    }

    public func socialSignIn(
        provider: SocialProvider,
        idToken: String,
        tenantId: String,
        name: String?,
        session: URLSession
    ) async throws -> AuthSession {
        let body = SocialLoginBody(provider: provider.rawValue, idToken: idToken, tenantId: tenantId, name: name)

        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/social"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.socialAuthError(for: http.statusCode, data: data)
        }
        do {
            let envelope = try JSONDecoder().decode(SocialSessionEnvelope.self, from: data)
            return AuthSession(
                accessToken: envelope.tokens.accessToken,
                refreshToken: envelope.tokens.refreshToken,
                user: envelope.user
            )
        } catch {
            throw SocialAuthError.invalidResponse
        }
    }

    // MARK: - Plumbing

    private struct SocialLoginBody: Encodable {
        let provider: String
        let idToken: String
        let tenantId: String
        /// Omitted entirely (not sent as `null`) when nil, matching
        /// `SocialLoginSchema.name` being `.optional()` rather than
        /// nullable.
        let name: String?
    }

    private struct SocialSessionEnvelope: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let tokens: Tokens
        let user: AuthUser
    }

    private struct ServerErrorBody: Decodable {
        let error: String
    }

    private static func socialAuthError(for statusCode: Int, data: Data) -> SocialAuthError {
        let message = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.error
        switch statusCode {
        // Exact string from bamware-auth-service `authService.ts`'s
        // `UNVERIFIED_PROVIDER_EMAIL` constant.
        case 401 where message == "Provider email is not verified": return .unverifiedEmail
        case 401: return .invalidToken
        case 403: return .providerNotAllowed
        case 503: return .providerNotConfigured(message: message ?? "That sign-in option isn't configured yet.")
        case 400: return .validation
        default: return .http(statusCode: statusCode)
        }
    }
}
