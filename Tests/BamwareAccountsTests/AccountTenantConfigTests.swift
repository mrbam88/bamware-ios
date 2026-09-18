import Foundation
import Testing
@testable import BamwareAccounts

/// Config injection: tenant id, auth base URL, keychain service name, and
/// provider support all come from `AccountTenantConfig`, never a package
/// constant (bamware-ios#2 scope).
@Suite struct AccountTenantConfigTests {
    @Test func storesEveryFieldAsGiven() {
        let url = URL(string: "https://auth.example.com")!
        let config = AccountTenantConfig(
            tenantId: "example-tenant",
            authBaseURL: url,
            keychainService: "com.example.app.auth",
            supportsApple: true,
            supportsGoogle: false
        )

        #expect(config.tenantId == "example-tenant")
        #expect(config.authBaseURL == url)
        #expect(config.keychainService == "com.example.app.auth")
        #expect(config.supportsApple)
        #expect(!config.supportsGoogle)
    }

    @Test func providerSupportDefaultsToFalse() {
        let config = AccountTenantConfig(
            tenantId: "example-tenant",
            authBaseURL: URL(string: "https://auth.example.com")!,
            keychainService: "com.example.app.auth"
        )

        #expect(!config.supportsApple)
        #expect(!config.supportsGoogle)
    }

    @Test func configTenantIdFlowsIntoScenarioServiceSessions() async throws {
        let config = AccountTenantConfig(
            tenantId: "example-tenant",
            authBaseURL: URL(string: "https://auth.example.com")!,
            keychainService: "com.example.app.auth"
        )
        let service = AuthScenarioService(tenantId: config.tenantId)

        let session = try await service.signIn(
            email: AuthScenarioService.seededEmail, password: AuthScenarioService.seededPassword
        )

        #expect(session.user.tenantId == config.tenantId)
    }
}
