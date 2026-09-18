import Foundation
import Testing
@testable import BamwareAccounts

/// `AuthAPI.socialSignIn` wire contract against bamware-auth-service's
/// `POST /auth/social` (bamware-ios#4) — pinned through a recording
/// `URLProtocol`, nothing reaches the network.
///
/// This does NOT reuse `AuthAPITests`' `AuthRecordingProtocol`/
/// `AuthFixtures` — those live in a file this ticket doesn't own
/// (bamware-ios#2), and their static recorder isn't safe to share across
/// suites that may run concurrently. Self-contained instead.
@Suite(.serialized) struct AuthAPISocialSignInTests {
    private static let tenantId = "bamware-test-tenant"
    private let base = URL(string: "https://auth.test")!

    private func makeAPI() -> AuthAPI {
        let config = AccountTenantConfig(
            tenantId: Self.tenantId, authBaseURL: base, keychainService: "com.bamware.test.auth"
        )
        return AuthAPI(config: config)
    }

    init() {
        SocialAuthRecordingProtocol.reset()
    }

    // MARK: - Request shape

    @Test func sendsProviderIdTokenTenantIdAndName() async throws {
        let session = try await makeAPI().socialSignIn(
            provider: .apple, idToken: "id-token-abc", tenantId: Self.tenantId, name: "New Taster",
            session: SocialAuthRecordingProtocol.makeSession()
        )

        let request = try #require(SocialAuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/social")
        #expect(request.bodyKeys == ["provider", "idToken", "tenantId", "name"])
        #expect(request.jsonBody?["provider"] as? String == "apple")
        #expect(request.jsonBody?["idToken"] as? String == "id-token-abc")
        #expect(request.jsonBody?["tenantId"] as? String == Self.tenantId)
        #expect(request.jsonBody?["name"] as? String == "New Taster")

        #expect(session.accessToken == "fixture-access")
        #expect(session.refreshToken == "fixture-refresh")
    }

    /// First-sign-in name handling: when `name` is present it's sent
    /// as-is; the server falls back to its own claims/email only when the
    /// field is absent (`socialAuthService.ts`).
    @Test func omitsNameEntirelyWhenNil() async throws {
        _ = try await makeAPI().socialSignIn(
            provider: .google, idToken: "id-token-xyz", tenantId: Self.tenantId, name: nil,
            session: SocialAuthRecordingProtocol.makeSession()
        )

        let request = try #require(SocialAuthRecordingProtocol.requests.first)
        #expect(request.bodyKeys == ["provider", "idToken", "tenantId"])
        #expect(request.jsonBody?["name"] == nil)
    }

    @Test func googleProviderSendsRawValueGoogle() async throws {
        _ = try await makeAPI().socialSignIn(
            provider: .google, idToken: "tok", tenantId: Self.tenantId, name: nil,
            session: SocialAuthRecordingProtocol.makeSession()
        )
        let request = try #require(SocialAuthRecordingProtocol.requests.first)
        #expect(request.jsonBody?["provider"] as? String == "google")
    }

    // MARK: - Error mapping

    @Test func mapsUnverifiedProviderEmailTo401() async {
        await #expect(throws: SocialAuthError.unverifiedEmail) {
            _ = try await makeAPI().socialSignIn(
                provider: .apple, idToken: "unverified-token", tenantId: Self.tenantId, name: nil,
                session: SocialAuthRecordingProtocol.makeSession()
            )
        }
    }

    @Test func mapsInvalidTokenTo401() async {
        await #expect(throws: SocialAuthError.invalidToken) {
            _ = try await makeAPI().socialSignIn(
                provider: .apple, idToken: "bad-token", tenantId: Self.tenantId, name: nil,
                session: SocialAuthRecordingProtocol.makeSession()
            )
        }
    }

    @Test func mapsProviderNotAllowedTo403() async {
        await #expect(throws: SocialAuthError.providerNotAllowed) {
            _ = try await makeAPI().socialSignIn(
                provider: .apple, idToken: "tok", tenantId: "no-apple-tenant", name: nil,
                session: SocialAuthRecordingProtocol.makeSession()
            )
        }
    }

    @Test func mapsNotConfiguredTo503WithServerMessage() async {
        await #expect(throws: SocialAuthError.providerNotConfigured(message: "Google sign-in is not configured")) {
            _ = try await makeAPI().socialSignIn(
                provider: .google, idToken: "tok", tenantId: "no-google-config-tenant", name: nil,
                session: SocialAuthRecordingProtocol.makeSession()
            )
        }
    }
}

// MARK: - Recording protocol (self-contained — see suite doc)

final class SocialAuthRecordingProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?
        var headers: [String: String] = [:]

        var path: String { url.path }
        var bodyKeys: Set<String> {
            guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return [] }
            return Set(object.keys)
        }
        var jsonBody: [String: Any]? {
            guard let body else { return nil }
            return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
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
        config.protocolClasses = [SocialAuthRecordingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            // `URLSession` sometimes hands the body over as a stream in
            // transit rather than leaving `httpBody` populated — same
            // fallback as `AuthAPITests`' recording protocol.
            body: request.httpBody ?? Self.drain(request.httpBodyStream),
            headers: request.allHTTPHeaderFields ?? [:]
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        Self.lock.unlock()

        let (status, data) = SocialAuthFixtures.respond(to: entry)
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

/// Canned `POST /auth/social` responses, magic fixture inputs select each
/// error path (mirrors `authHandler.ts` / `socialAuthService.ts`).
enum SocialAuthFixtures {
    static func respond(to request: SocialAuthRecordingProtocol.Recorded) -> (Int, Data) {
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        func envelope(email: String, name: String, tenantId: String) -> Data {
            json([
                "tokens": ["accessToken": "fixture-access", "refreshToken": "fixture-refresh"],
                "user": ["userId": "user-fixture", "email": email, "name": name, "tenantId": tenantId],
            ])
        }
        guard request.method == "POST", request.path == "/auth/social" else {
            return (404, json(["error": "not_found"]))
        }
        let body = request.jsonBody
        let idToken = body?["idToken"] as? String ?? ""
        let tenantId = body?["tenantId"] as? String ?? ""
        let provider = body?["provider"] as? String ?? ""

        if idToken == "unverified-token" { return (401, json(["error": "Provider email is not verified"])) }
        if idToken == "bad-token" { return (401, json(["error": "Invalid or expired ID token"])) }
        if tenantId == "no-apple-tenant" { return (403, json(["error": "provider_not_allowed"])) }
        if tenantId == "no-google-config-tenant" {
            return (503, json(["error": "Google sign-in is not configured"]))
        }
        let email = "\(provider)-user@bamware.com"
        let name = body?["name"] as? String ?? "Fixture User"
        return (200, envelope(email: email, name: name, tenantId: tenantId))
    }
}
