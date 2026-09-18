import Foundation
import Observation
import Security

/// Where the signed-in session is kept between launches.
public protocol AuthSessionPersisting: AnyObject, Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// Keychain-backed persistence (generic password, this app only, no iCloud
/// sync). Tokens never touch UserDefaults — the keychain survives reinstalls
/// less predictably but is the only right place for bearer tokens.
public final class KeychainSessionStore: AuthSessionPersisting {
    private let service: String
    private let account = "session"

    /// - Parameter service: the `kSecAttrService` value sessions are scoped
    ///   under (from `AccountTenantConfig.keychainService`). Should be
    ///   unique per app so two tenant apps on one device never collide.
    public init(service: String) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Ephemeral persistence for scenario launches and package tests: every
/// process starts signed out, deterministically.
public final class InMemorySessionStore: AuthSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func load() -> AuthSession? { lock.withLock { session } }
    public func save(_ session: AuthSession) { lock.withLock { self.session = session } }
    public func clear() { lock.withLock { session = nil } }
}

/// App-wide signed-in state. `@Observable` so signed-in/out UI flips live.
/// Apps own the instance (and its lifetime/injection) — this package does
/// not vend a singleton, since which persistence backend to use is a
/// per-app, per-launch-mode decision.
///
/// `session` is lock-guarded (bamware-ios#3): `SessionRefresher` is an actor
/// and stores/clears sessions from a background refresh, concurrently with
/// whatever isolation domain the app's UI reads it from. `@unchecked
/// Sendable` is the manual guarantee for that — every access to `session`
/// goes through `lock`.
@Observable
public final class AccountSessionStore: @unchecked Sendable {
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var _session: AuthSession?
    @ObservationIgnored private let persistence: any AuthSessionPersisting

    public init(persistence: any AuthSessionPersisting) {
        self.persistence = persistence
        _session = persistence.load()
    }

    /// Manually tracked (`access`/`withMutation`) rather than a plain
    /// `@Observable`-instrumented stored property, since the backing value
    /// is lock-guarded for cross-actor writes from `SessionRefresher`.
    public var session: AuthSession? {
        access(keyPath: \.session)
        return lock.withLock { _session }
    }

    public var isSignedIn: Bool { session != nil }

    /// The stored access token's `exp` claim, decoded locally (no network
    /// call) — nil when signed out or the token cannot be decoded.
    public var accessExpiresAt: Date? {
        session.flatMap { JWTExpiry.expiresAt($0.accessToken) }
    }

    public func store(_ session: AuthSession) {
        withMutation(keyPath: \.session) {
            lock.withLock { _session = session }
        }
        persistence.save(session)
    }

    public func clear() {
        withMutation(keyPath: \.session) {
            lock.withLock { _session = nil }
        }
        persistence.clear()
    }
}
