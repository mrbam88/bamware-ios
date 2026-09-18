import Foundation

/// Deterministic stand-in for `AuthAPI`: no network, no persistence, fresh
/// per process. Apps resolve it in place of `AuthAPI` for UI tests and
/// previews — account flows are orthogonal to any app-specific scenario
/// system, so one in-memory auth world can back every scenario.
///
/// Seeded account defaults mirror common auth-service seed scripts:
/// `tester@bamware.com` / `BrewDesk1!` ("Test Taster"), overridable per app.
/// Registered accounts live for the process lifetime, so sign-out →
/// sign-in-again works across screen instances within one launch.
public actor AuthScenarioService: AccountAuthServing {
    public static let seededEmail = "tester@bamware.com"
    public static let seededPassword = "BrewDesk1!"
    public static let seededName = "Test Taster"

    private struct Account {
        let user: AuthUser
        let password: String
    }

    private let tenantId: String
    private var accountsByEmail: [String: Account] = [:]
    private var emailByAccessToken: [String: String] = [:]
    private var counter = 0

    /// - Parameters:
    ///   - tenantId: the tenant id seeded/registered users are stamped with
    ///     (from `AccountTenantConfig.tenantId`).
    ///   - seeded: whether to pre-populate the default seeded account.
    public init(tenantId: String, seeded: Bool = true) {
        self.tenantId = tenantId
        if seeded {
            let user = AuthUser(
                userId: "scenario-user-seeded",
                email: Self.seededEmail,
                name: Self.seededName,
                tenantId: tenantId
            )
            accountsByEmail[Self.seededEmail] = Account(user: user, password: Self.seededPassword)
        }
    }

    public func register(email: String, password: String, name: String) async throws -> AuthSession {
        let key = normalize(email)
        guard accountsByEmail[key] == nil else { throw AuthAPIError.emailAlreadyRegistered }
        guard password.count >= 8 else { throw AuthAPIError.validation }
        counter += 1
        let user = AuthUser(
            userId: "scenario-user-\(counter)",
            email: key,
            name: name,
            tenantId: tenantId
        )
        accountsByEmail[key] = Account(user: user, password: password)
        return session(for: user)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let key = normalize(email)
        guard let account = accountsByEmail[key], account.password == password else {
            throw AuthAPIError.invalidCredentials
        }
        return session(for: account.user)
    }

    public func deleteAccount(accessToken: String) async throws {
        // Idempotent, like the real endpoint: unknown token → already gone.
        guard let email = emailByAccessToken.removeValue(forKey: accessToken) else { return }
        accountsByEmail.removeValue(forKey: email)
    }

    // MARK: - Helpers

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func session(for user: AuthUser) -> AuthSession {
        let token = "scenario-access-\(user.userId)-\(counter)"
        emailByAccessToken[token] = user.email
        return AuthSession(accessToken: token, refreshToken: "scenario-refresh-\(user.userId)", user: user)
    }
}
