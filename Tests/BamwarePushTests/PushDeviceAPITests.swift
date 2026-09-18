import Foundation
import Testing
@testable import BamwarePush

/// `PushDeviceAPI` wire contract against bamware-infra#8's documented
/// `POST /devices` / `DELETE /devices/:deviceId` shape, pinned through a
/// recording `URLProtocol` — nothing reaches the network (the service isn't
/// built yet). Pattern ported from `BamwareAccountsTests.AuthAPITests`'
/// `AuthRecordingProtocol`.
@Suite(.serialized) struct PushDeviceAPITests {
    private let base = URL(string: "https://push.test")!

    private func makeAPI() -> PushDeviceAPI {
        let config = PushConfig(baseURL: base, tenantId: "bamware-test-tenant")
        return PushDeviceAPI(config: config, session: PushRecordingProtocol.makeSession())
    }

    init() {
        PushRecordingProtocol.reset()
    }

    @Test func registerSendsDeviceIdTokenPlatformPreferencesAndBearer() async throws {
        try await makeAPI().register(
            deviceId: "device-1", token: "abc123", platform: "ios",
            preferences: ["matches": true, "messages": false], bearerToken: "access-token"
        )

        let request = try #require(PushRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/devices")
        #expect(request.headers["Authorization"] == "Bearer access-token")
        #expect(request.bodyKeys == ["deviceId", "token", "platform", "preferences"])
    }

    @Test func registerOmitsPreferencesKeyWhenEmpty() async throws {
        try await makeAPI().register(
            deviceId: "device-1", token: "abc123", platform: "ios",
            preferences: [:], bearerToken: "access-token"
        )

        let request = try #require(PushRecordingProtocol.requests.first)
        #expect(request.bodyKeys == ["deviceId", "token", "platform"])
    }

    @Test func registerMapsNon2xxToHTTPError() async {
        await #expect(throws: PushDeviceAPIError.http(statusCode: 500)) {
            try await makeAPI().register(
                deviceId: "boom-device", token: "abc123", platform: "ios",
                preferences: [:], bearerToken: "access-token"
            )
        }
    }

    @Test func deleteSendsBearerAndPath() async throws {
        try await makeAPI().deleteDevice(deviceId: "device-7", bearerToken: "access-token")

        let request = try #require(PushRecordingProtocol.requests.first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/devices/device-7")
        #expect(request.headers["Authorization"] == "Bearer access-token")
    }

    /// Idempotent delete: an already-gone device is 404, treated as success
    /// (matches `AuthAPI.deleteAccount`'s convention for `DELETE /auth/account`).
    @Test func deleteTreats404AsSuccess() async throws {
        try await makeAPI().deleteDevice(deviceId: "already-gone", bearerToken: "access-token")
        #expect(PushRecordingProtocol.requests.count == 1)
    }
}

/// Recording loader for `PushDeviceAPI` tests. Only installed on sessions
/// built by `makeSession()`.
final class PushRecordingProtocol: URLProtocol {
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
        config.protocolClasses = [PushRecordingProtocol.self]
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

        let (status, data) = PushFixtures.respond(to: entry)
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

/// Canned bamware-push-service (D12/bamware-infra#8) responses. Magic
/// fixture inputs (`boom-device`, `already-gone`) select error/edge paths;
/// this service isn't built yet, so these are contract-shape fixtures, not
/// verified against a live implementation.
enum PushFixtures {
    static func respond(to request: PushRecordingProtocol.Recorded) -> (Int, Data) {
        func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        let bodyObject = request.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        switch (request.method, request.path) {
        case ("POST", "/devices"):
            if bodyObject?["deviceId"] as? String == "boom-device" {
                return (500, json(["error": "boom"]))
            }
            return (200, json(["ok": true]))
        case ("DELETE", _) where request.path.hasPrefix("/devices/"):
            if request.path == "/devices/already-gone" {
                return (404, json(["error": "not found"]))
            }
            return (200, json(["ok": true]))
        default:
            return (404, json(["error": "unhandled fixture path"]))
        }
    }
}
