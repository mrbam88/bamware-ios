import Foundation
import Testing
@testable import BamwareAccounts

/// The deterministic auth world UI tests lean on. Ported from BrewDesk's
/// `AuthScenarioServiceTests`, generalized for the injected `tenantId`
/// (bamware-ios#2).
@Suite struct AuthScenarioServiceTests {
    private static let tenantId = "test-tenant"

    @Test func seededAccountSignsIn() async throws {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        let session = try await service.signIn(
            email: AuthScenarioService.seededEmail,
            password: AuthScenarioService.seededPassword
        )
        #expect(session.user.name == AuthScenarioService.seededName)
        #expect(session.user.tenantId == Self.tenantId)
        #expect(!session.accessToken.isEmpty)
    }

    @Test func wrongPasswordThrowsInvalidCredentials() async {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await service.signIn(
                email: AuthScenarioService.seededEmail, password: "WrongPass99!"
            )
        }
    }

    @Test func registerThenSignInRoundTrips() async throws {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        let registered = try await service.register(
            email: "New@Bamware.com", password: "FlatWhite11!", name: "New Taster"
        )
        #expect(registered.user.email == "new@bamware.com") // normalized

        let signedIn = try await service.signIn(email: "new@bamware.com", password: "FlatWhite11!")
        #expect(signedIn.user.userId == registered.user.userId)
    }

    @Test func registerDuplicateEmailThrows() async throws {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        await #expect(throws: AuthAPIError.emailAlreadyRegistered) {
            _ = try await service.register(
                email: AuthScenarioService.seededEmail, password: "FlatWhite11!", name: "Dup"
            )
        }
    }

    @Test func shortPasswordThrowsValidation() async {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        await #expect(throws: AuthAPIError.validation) {
            _ = try await service.register(email: "short@bamware.com", password: "short", name: "S")
        }
    }

    @Test func deleteAccountRemovesAccountAndIsIdempotent() async throws {
        let service = AuthScenarioService(tenantId: Self.tenantId)
        let session = try await service.signIn(
            email: AuthScenarioService.seededEmail,
            password: AuthScenarioService.seededPassword
        )

        try await service.deleteAccount(accessToken: session.accessToken)
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await service.signIn(
                email: AuthScenarioService.seededEmail,
                password: AuthScenarioService.seededPassword
            )
        }
        // Idempotent, like the real endpoint.
        try await service.deleteAccount(accessToken: session.accessToken)
        try await service.deleteAccount(accessToken: "never-issued")
    }

    // MARK: - Config injection (bamware-ios#2)

    @Test func differentTenantsStampDifferentTenantIds() async throws {
        let a = AuthScenarioService(tenantId: "tenant-a")
        let b = AuthScenarioService(tenantId: "tenant-b")

        let sessionA = try await a.signIn(
            email: AuthScenarioService.seededEmail, password: AuthScenarioService.seededPassword
        )
        let sessionB = try await b.signIn(
            email: AuthScenarioService.seededEmail, password: AuthScenarioService.seededPassword
        )

        #expect(sessionA.user.tenantId == "tenant-a")
        #expect(sessionB.user.tenantId == "tenant-b")
    }

    @Test func unseededServiceHasNoSeededAccount() async {
        let service = AuthScenarioService(tenantId: Self.tenantId, seeded: false)
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await service.signIn(
                email: AuthScenarioService.seededEmail, password: AuthScenarioService.seededPassword
            )
        }
    }
}
