import Foundation
import Testing
@testable import BamwareAccounts

/// `AuthAPI` wire contract against bamware-auth-service, pinned through a
/// recording URL protocol — nothing reaches the network. Ported from
/// BrewDesk's `AuthAPITests`; the fixture responder here is a trimmed,
/// auth-only copy of BrewDesk's `EngineFixtures.authRespond`, since the rest
/// of `EngineFixtures` is venue-engine specific and out of this package's
/// scope (bamware-ios#2). Generalized for `AccountTenantConfig` injection —
/// the tenant id used to come from a hardcoded `BrewDeskTenant.id`.
@Suite(.serialized) struct AuthAPITests {
    private static let tenantId = "bamware-test-tenant"
    private let base = URL(string: "https://auth.test")!

    private func makeAPI(tenantId: String = AuthAPITests.tenantId) -> AuthAPI {
        let config = AccountTenantConfig(
            tenantId: tenantId,
            authBaseURL: base,
            keychainService: "com.bamware.test.auth"
        )
        return AuthAPI(config: config, session: AuthRecordingProtocol.makeSession())
    }

    init() {
        AuthRecordingProtocol.reset()
    }

    // MARK: - Register

    @Test func registerSendsTenantScopedBodyAndDecodesSession() async throws {
        let session = try await makeAPI().register(
            email: "new@bamware.com", password: "FlatWhite11!", name: "New Taster"
        )

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/register")
        #expect(request.bodyKeys == ["email", "password", "name", "tenantId"])
        #expect(request.contains(Self.tenantId))

        #expect(session.accessToken == "fixture-access")
        #expect(session.refreshToken == "fixture-refresh")
        #expect(session.user.email == "new@bamware.com")
        #expect(session.user.tenantId == Self.tenantId)
    }

    @Test func registerMaps409ToEmailAlreadyRegistered() async {
        await #expect(throws: AuthAPIError.emailAlreadyRegistered) {
            _ = try await makeAPI().register(
                email: "taken@bamware.com", password: "FlatWhite11!", name: "Dup"
            )
        }
    }

    // MARK: - Sign in

    @Test func signInSendsTenantScopedBody() async throws {
        _ = try await makeAPI().signIn(email: "tester@bamware.com", password: "FlatWhite11!")

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/login")
        #expect(request.bodyKeys == ["email", "password", "tenantId"])
        #expect(request.contains(Self.tenantId))
    }

    @Test func signInMaps401ToInvalidCredentials() async {
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await makeAPI().signIn(email: "tester@bamware.com", password: "WrongPass99!")
        }
    }

    // MARK: - Delete account

    @Test func deleteAccountSendsBearerToken() async throws {
        try await makeAPI().deleteAccount(accessToken: "token-123")

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/auth/account")
        #expect(request.headers["Authorization"] == "Bearer token-123")
        #expect(request.body == nil)
    }

    /// The ordered-deletion pattern depends on retries being safe: the server
    /// treats "already gone" as 404 and the client treats 404 as success.
    @Test func deleteAccountTreats404AsSuccess() async throws {
        try await makeAPI().deleteAccount(accessToken: "already-gone")
        #expect(AuthRecordingProtocol.requests.count == 1)
    }

    // MARK: - Refresh (bamware-ios#3)

    @Test func refreshSendsRefreshTokenBodyAndDecodesRotatedSession() async throws {
        let session = try await makeAPI().refresh(refreshToken: "old-refresh-token")

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/refresh")
        #expect(request.bodyKeys == ["refreshToken"])
        #expect(request.contains("old-refresh-token"))

        #expect(session.accessToken == "fixture-access")
        #expect(session.refreshToken == "fixture-refresh")
    }

    @Test func refreshReuseMapsAnyRefresh401ToHTTPError() async {
        await #expect(throws: AuthAPIError.http(statusCode: 401)) {
            _ = try await makeAPI().refresh(refreshToken: "already-rotated-out")
        }
    }

    // MARK: - Config injection (bamware-ios#2)

    @Test func baseURLComesFromConfigNotAConstant() async throws {
        let otherBase = URL(string: "https://other-auth.test")!
        let config = AccountTenantConfig(
            tenantId: Self.tenantId, authBaseURL: otherBase, keychainService: "svc"
        )
        let api = AuthAPI(config: config, session: AuthRecordingProtocol.makeSession())
        #expect(api.baseURL == otherBase)
    }

    @Test func differentTenantIdsProduceDifferentRequestBodies() async throws {
        _ = try await makeAPI(tenantId: "tenant-one").signIn(email: "a@bamware.com", password: "FlatWhite11!")
        let first = try #require(AuthRecordingProtocol.requests.first)
        #expect(first.contains("tenant-one"))
        #expect(!first.contains("tenant-two"))

        AuthRecordingProtocol.reset()
        _ = try await makeAPI(tenantId: "tenant-two").signIn(email: "a@bamware.com", password: "FlatWhite11!")
        let second = try #require(AuthRecordingProtocol.requests.first)
        #expect(second.contains("tenant-two"))
    }
}

/// Recording loader for `AuthAPI` tests: records every request a `URLSession`
/// issues and answers it from a small, auth-only fixture set. Only installed
/// on sessions built by `makeSession()`, so it cannot disturb other suites.
final class AuthRecordingProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?
        var headers: [String: String] = [:]

        var path: String { url.path }
        var bodyKeys: Set<String> {
            guard let body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return [] }
            return Set(object.keys)
        }
        /// True when `needle` appears anywhere in the absolute URL or body.
        func contains(_ needle: String) -> Bool {
            if url.absoluteString.contains(needle) { return true }
            guard let body, let text = String(data: body, encoding: .utf8) else { return false }
            return text.contains(needle)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthRecordingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: request.httpBody ?? Self.drain(request.httpBodyStream),
            headers: request.allHTTPHeaderFields ?? [:]
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        Self.lock.unlock()

        let (status, data) = AuthFixtures.respond(to: entry)
        let response = HTTPURLResponse(
            url: entry.url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Canned bamware-auth-service responses, auth endpoints only. Mirrors
/// `authHandler.ts`: register 201/409, login 200/401, delete 200/404 with a
/// Bearer check. Magic fixture inputs select the error paths.
enum AuthFixtures {
    static func respond(to request: AuthRecordingProtocol.Recorded) -> (Int, Data) {
        func json(_ object: Any) -> Data {
            try! JSONSerialization.data(withJSONObject: object)
        }
        func envelope(email: String, name: String, tenantId: String) -> Data {
            json([
                "tokens": ["accessToken": "fixture-access", "refreshToken": "fixture-refresh"],
                "user": [
                    "userId": "user-fixture", "email": email, "name": name,
                    "role": "customer", "tenantId": tenantId,
                    "createdAt": "2026-08-01T00:00:00.000Z",
                    "schemaVersion": 1, "emailVerified": false,
                ],
            ])
        }
        let bodyObject = request.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let tenantId = bodyObject?["tenantId"] as? String ?? "unknown-tenant"
        switch (request.method, request.path) {
        case ("POST", "/auth/register"):
            let email = bodyObject?["email"] as? String ?? ""
            if email == "taken@bamware.com" { return (409, json(["error": "Email already registered"])) }
            return (201, envelope(email: email, name: bodyObject?["name"] as? String ?? "", tenantId: tenantId))
        case ("POST", "/auth/login"):
            let email = bodyObject?["email"] as? String ?? ""
            if bodyObject?["password"] as? String == "WrongPass99!" {
                return (401, json(["error": "Invalid email or password"]))
            }
            return (200, envelope(email: email, name: "Fixture User", tenantId: tenantId))
        case ("POST", "/auth/refresh"):
            let refreshToken = bodyObject?["refreshToken"] as? String ?? ""
            if refreshToken == "already-rotated-out" {
                return (401, json(["error": "refresh_reused"]))
            }
            return (200, envelope(email: "tester@bamware.com", name: "Fixture User", tenantId: tenantId))
        case ("DELETE", "/auth/account"):
            guard request.headers["Authorization"]?.hasPrefix("Bearer ") == true else {
                return (401, json(["error": "Missing bearer token"]))
            }
            if request.headers["Authorization"] == "Bearer already-gone" {
                return (404, json(["error": "not_found"]))
            }
            return (200, json(["ok": true]))
        default:
            return (404, json(["error": "not_found"]))
        }
    }
}
