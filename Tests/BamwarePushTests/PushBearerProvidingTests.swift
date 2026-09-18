import Foundation
import Testing
import BamwareAccounts
@testable import BamwarePush

/// `PushBearerProviding` wiring: `SessionRefresher` (bamware-ios#3, already
/// merged) conforms directly with no adapter code, and
/// `AccountSessionStoreBearerProvider` is the "else the current access
/// token" fallback the issue calls for.
@Suite struct PushBearerProvidingTests {
    private static func user() -> AuthUser {
        AuthUser(userId: "u1", email: "tester@bamware.com", name: "Tester", tenantId: "test-tenant")
    }

    /// A JWT with a real, decodable `exp` claim far enough in the future
    /// that `SessionRefresher` never needs to actually refresh for this test.
    private static func session(accessToken: String = "access-1") -> AuthSession {
        func segment(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = segment(["alg": "HS256", "typ": "JWT"])
        let payload = segment(["exp": Date().addingTimeInterval(3_600).timeIntervalSince1970, "sub": "u1"])
        return AuthSession(accessToken: "\(header).\(payload).sig", refreshToken: "refresh-1", user: user())
    }

    @Test func sessionRefresherConformsToPushBearerProviding() async throws {
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session())
        let refresher = SessionRefresher(refreshing: NeverCalledRefreshing(), sessions: store)

        let bearer: any PushBearerProviding = refresher
        let token = try await bearer.validAccessToken()
        #expect(!token.isEmpty)
    }

    @Test func accountSessionStoreBearerProviderReadsStoredToken() async throws {
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(accessToken: "stored-access-token"))

        let provider = AccountSessionStoreBearerProvider(sessions: store)
        let token = try await provider.validAccessToken()
        #expect(token.contains("."), "returns the raw stored access token (a JWT)")
    }

    @Test func accountSessionStoreBearerProviderThrowsWhenSignedOut() async {
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        let provider = AccountSessionStoreBearerProvider(sessions: store)

        await #expect(throws: PushBearerError.notSignedIn) {
            _ = try await provider.validAccessToken()
        }
    }

    @Test func fakePushBearerProviderThrowsWhenNoTokenScripted() async {
        let fake = FakePushBearerProvider()
        await #expect(throws: FakePushBearerProvider.Failure.notSignedIn) {
            _ = try await fake.validAccessToken()
        }
    }

    private struct NeverCalledRefreshing: AccountRefreshing {
        func refresh(refreshToken: String, user: AuthUser) async throws -> AuthSession {
            Issue.record("refresh should not be called for a token with plenty of time left")
            throw AuthAPIError.invalidResponse
        }
    }
}
