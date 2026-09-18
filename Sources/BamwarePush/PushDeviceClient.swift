import Foundation

// Wire client for bamware-push-service (D12, bamware-infra#8 — not built
// yet at the time this package was written; coded against the issue's
// documented contract and the existing dating-service shape in
// `bamware-dating-service/src/schemas/deviceSchemas.ts`).
//
// Endpoint contract (bamware-infra#8):
// - `POST /devices` `{deviceId, token, platform, preferences?}` (Bearer) →
//   200/201 on success.
// - `DELETE /devices/:deviceId` (Bearer) → success. Treated the same way
//   `AuthAPI.deleteAccount` treats a 404 (see `AuthAPI.swift` in
//   `BamwareAccounts`): idempotent, so a device already removed
//   server-side is not an error the caller needs to handle.

/// Config for talking to the push service. Apps own tenant identity;
/// nothing in this package is a constant (same shape as
/// `AccountTenantConfig`).
public struct PushConfig: Sendable {
    public let baseURL: URL

    /// Not sent in the `POST /devices` / `DELETE /devices` bodies —
    /// bamware-infra#8's contract has the service derive tenant from the
    /// bearer's auth-middleware claim, not from a client-supplied field.
    /// Kept as a config value (not a constant) for parity with
    /// `AccountTenantConfig` and in case a future contract needs it
    /// explicitly. See the package README's spec-gap notes.
    public let tenantId: String

    public init(baseURL: URL, tenantId: String) {
        self.baseURL = baseURL
        self.tenantId = tenantId
    }
}

public enum PushDeviceAPIError: Error, Equatable, Sendable {
    case invalidResponse
    case http(statusCode: Int)
}

/// Seam for the device-registration wire calls. `PushDeviceAPI` is the live
/// `URLSession` client; tests use `FakePushDeviceClient`.
public protocol PushDeviceRegistering: Sendable {
    func register(
        deviceId: String,
        token: String,
        platform: String,
        preferences: [String: Bool],
        bearerToken: String
    ) async throws

    func deleteDevice(deviceId: String, bearerToken: String) async throws
}

public struct PushDeviceAPI: PushDeviceRegistering, Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(config: PushConfig, session: URLSession = .shared) {
        self.baseURL = config.baseURL
        self.session = session
    }

    public func register(
        deviceId: String,
        token: String,
        platform: String,
        preferences: [String: Bool],
        bearerToken: String
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let body = RegisterBody(
            deviceId: deviceId,
            token: token,
            platform: platform,
            preferences: preferences.isEmpty ? nil : preferences
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    public func deleteDevice(deviceId: String, bearerToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/devices/\(deviceId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        try Self.check(response, treat404AsSuccess: true)
    }

    private struct RegisterBody: Encodable {
        let deviceId: String
        let token: String
        let platform: String
        let preferences: [String: Bool]?
    }

    private static func check(_ response: URLResponse, treat404AsSuccess: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else { throw PushDeviceAPIError.invalidResponse }
        if (200...299).contains(http.statusCode) { return }
        if treat404AsSuccess, http.statusCode == 404 { return }
        throw PushDeviceAPIError.http(statusCode: http.statusCode)
    }
}

/// Deterministic double for tests — records every call, never touches the
/// network.
public actor FakePushDeviceClient: PushDeviceRegistering {
    public struct RegisterCall: Equatable, Sendable {
        public let deviceId: String
        public let token: String
        public let platform: String
        public let preferences: [String: Bool]
        public let bearerToken: String
    }

    public struct DeleteCall: Equatable, Sendable {
        public let deviceId: String
        public let bearerToken: String
    }

    public enum Failure: Error, Sendable { case boom }

    public private(set) var registerCalls: [RegisterCall] = []
    public private(set) var deleteCalls: [DeleteCall] = []
    private var registerError: Failure?
    private var deleteError: Failure?

    public init() {}

    public func setRegisterError(_ error: Failure?) { registerError = error }
    public func setDeleteError(_ error: Failure?) { deleteError = error }

    public func register(
        deviceId: String,
        token: String,
        platform: String,
        preferences: [String: Bool],
        bearerToken: String
    ) async throws {
        if let registerError { throw registerError }
        registerCalls.append(
            RegisterCall(deviceId: deviceId, token: token, platform: platform, preferences: preferences, bearerToken: bearerToken)
        )
    }

    public func deleteDevice(deviceId: String, bearerToken: String) async throws {
        if let deleteError { throw deleteError }
        deleteCalls.append(DeleteCall(deviceId: deviceId, bearerToken: bearerToken))
    }
}
