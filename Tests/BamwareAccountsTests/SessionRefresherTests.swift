import Foundation
import Testing
@testable import BamwareAccounts

/// `SessionRefresher`: proactive refresh, single-flight, 401-retry-once,
/// revoked → signed out with reason, rotation stores the new pair
/// (bamware-ios#3). A fake clock and a fake `AccountRefreshing` stand in for
/// wall-clock time and the network — nothing here sleeps for real time or
/// hits `URLSession`.
@Suite struct SessionRefresherTests {
    private static let tenantId = "test-tenant"

    private static func user() -> AuthUser {
        AuthUser(userId: "u1", email: "tester@bamware.com", name: "Tester", tenantId: tenantId)
    }

    /// A JWT with a real, decodable `exp` claim and a throwaway signature —
    /// `SessionRefresher` never verifies the signature, only decodes `exp`.
    private static func jwt(exp: Date) -> String {
        func segment(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = segment(["alg": "HS256", "typ": "JWT"])
        let payload = segment(["exp": exp.timeIntervalSince1970, "sub": "u1"])
        return "\(header).\(payload).sig"
    }

    private static func session(expiresIn seconds: TimeInterval, from now: Date, refreshToken: String = "refresh-1") -> AuthSession {
        AuthSession(accessToken: jwt(exp: now.addingTimeInterval(seconds)), refreshToken: refreshToken, user: user())
    }

    // MARK: - Fakes

    private final class TestClock: RefreshClock, @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(_ date: Date) { current = date }
        func now() -> Date { lock.withLock { current } }
        func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    }

    /// Records every call; `gate` (if set) makes `refresh` await a signal
    /// before returning, so tests can force concurrent callers to overlap.
    private actor FakeRefreshing: AccountRefreshing {
        private(set) var callCount = 0
        private(set) var receivedTokens: [String] = []
        var nextResult: Result<AuthSession, Error>
        private var gate: (@Sendable () async -> Void)?

        init(result: Result<AuthSession, Error>, gate: (@Sendable () async -> Void)? = nil) {
            self.nextResult = result
            self.gate = gate
        }

        func setGate(_ gate: @escaping @Sendable () async -> Void) { self.gate = gate }
        func setResult(_ result: Result<AuthSession, Error>) { nextResult = result }

        func refresh(refreshToken: String) async throws -> AuthSession {
            callCount += 1
            receivedTokens.append(refreshToken)
            if let gate { await gate() }
            return try nextResult.get()
        }
    }

    // MARK: - Proactive refresh (< 2 min left)

    @Test func proactiveRefreshWhenLessThanTwoMinutesLeft() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let clock = TestClock(now)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 90, from: now)) // < 120s window

        let newPair = Self.session(expiresIn: 900, from: now, refreshToken: "refresh-2")
        let fake = FakeRefreshing(result: .success(newPair))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: clock)

        let token = try await refresher.validAccessToken()

        #expect(token == newPair.accessToken)
        #expect(await fake.callCount == 1)
    }

    @Test func noRefreshWhenComfortablyValid() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let clock = TestClock(now)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        let current = Self.session(expiresIn: 600, from: now) // well outside 120s window
        store.store(current)

        let fake = FakeRefreshing(result: .failure(AuthAPIError.http(statusCode: 401)))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: clock)

        let token = try await refresher.validAccessToken()

        #expect(token == current.accessToken)
        #expect(await fake.callCount == 0) // never touched the network
    }

    // MARK: - Rotation stores the new pair

    @Test func successfulRefreshRotatesStoredPair() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 30, from: now, refreshToken: "refresh-old"))

        let newPair = Self.session(expiresIn: 900, from: now, refreshToken: "refresh-new")
        let fake = FakeRefreshing(result: .success(newPair))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        _ = try await refresher.validAccessToken()

        #expect(store.session?.accessToken == newPair.accessToken)
        #expect(store.session?.refreshToken == "refresh-new")
        #expect(await fake.receivedTokens == ["refresh-old"]) // the OLD token was presented
    }

    // MARK: - Single-flight under concurrency

    @Test func concurrentCallersShareOneInFlightRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 30, from: now)) // needs refresh

        let newPair = Self.session(expiresIn: 900, from: now, refreshToken: "refresh-rotated")
        let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

        let fake = FakeRefreshing(result: .success(newPair))
        await fake.setGate {
            gateContinuation.yield() // tell the test "a refresh call is in flight"
            for await _ in releaseStream { break } // wait for the test to release it
        }
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        async let first = refresher.validAccessToken()
        async let second = refresher.validAccessToken()
        async let third = refresher.validAccessToken()

        var gateIterator = gateStream.makeAsyncIterator()
        _ = await gateIterator.next() // first caller's refresh is now in flight
        releaseContinuation.yield() // let it complete
        releaseContinuation.finish()

        let results = try await [first, second, third]

        #expect(results.allSatisfy { $0 == newPair.accessToken })
        #expect(await fake.callCount == 1) // only ONE network refresh happened
    }

    // MARK: - 401-retry-once

    @Test func refreshAfterUnauthorizedForcesOneRefreshEvenIfNotYetExpired() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 600, from: now)) // exp says it's fine

        let newPair = Self.session(expiresIn: 900, from: now, refreshToken: "refresh-after-401")
        let fake = FakeRefreshing(result: .success(newPair))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        let token = try await refresher.refreshAfterUnauthorized()

        #expect(token == newPair.accessToken)
        #expect(await fake.callCount == 1) // forced despite exp being far off
    }

    @Test func secondConsecutive401AfterRetryEndsTheSession() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 600, from: now))

        let fake = FakeRefreshing(result: .failure(AuthAPIError.http(statusCode: 401)))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        await #expect(throws: SessionRefresherError.sessionEnded(reason: .refreshRejected)) {
            _ = try await refresher.refreshAfterUnauthorized()
        }
        #expect(store.session == nil) // cleared, not left dangling
    }

    // MARK: - Revoked → signed out with reason

    @Test func refreshReuseReportedAs401EndsSessionAndClearsStore() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 30, from: now)) // triggers proactive refresh

        // auth-service A2: reuse of a rotated-out refresh token → 401 refresh_reused.
        let fake = FakeRefreshing(result: .failure(AuthAPIError.http(statusCode: 401)))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        await #expect(throws: SessionRefresherError.sessionEnded(reason: .refreshRejected)) {
            _ = try await refresher.validAccessToken()
        }
        #expect(!store.isSignedIn)
    }

    @Test func nonRevokeErrorsDoNotClearTheSession() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(Self.session(expiresIn: 30, from: now))

        let fake = FakeRefreshing(result: .failure(AuthAPIError.http(statusCode: 500)))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(now))

        await #expect(throws: AuthAPIError.http(statusCode: 500)) {
            _ = try await refresher.validAccessToken()
        }
        #expect(store.isSignedIn) // a 500 is transient, not a revoke — session stays
    }

    @Test func signOutOnSessionEndSurfacesFriendlyMessageOnAccountModel() {
        let sessions = AccountSessionStore(persistence: InMemorySessionStore())
        sessions.store(Self.session(expiresIn: 600, from: Date()))
        let model = AccountModel(auth: NeverCalledAuth(), sessions: sessions)

        model.signOutOnSessionEnd(reason: .refreshRejected)

        #expect(!sessions.isSignedIn)
        #expect(model.phase == .failed(message: "You were signed out because this session ended. Sign in again to continue."))
    }

    @Test func notSignedInThrowsWithoutTouchingTheNetwork() async throws {
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        let fake = FakeRefreshing(result: .failure(AuthAPIError.http(statusCode: 401)))
        let refresher = SessionRefresher(refreshing: fake, sessions: store, clock: TestClock(Date()))

        await #expect(throws: SessionRefresherError.notSignedIn) {
            _ = try await refresher.validAccessToken()
        }
        #expect(await fake.callCount == 0)
    }

    // MARK: - JWT `exp` decoding

    @Test func accessExpiresAtDecodesTheExpClaim() {
        let exp = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(AuthSession(accessToken: Self.jwt(exp: exp), refreshToken: "r", user: Self.user()))

        let decodedExp = store.accessExpiresAt?.timeIntervalSince1970 ?? -1
        #expect(abs(decodedExp - exp.timeIntervalSince1970) < 0.001)
    }

    @Test func accessExpiresAtIsNilForAMalformedToken() {
        let store = AccountSessionStore(persistence: InMemorySessionStore())
        store.store(AuthSession(accessToken: "not-a-jwt", refreshToken: "r", user: Self.user()))
        #expect(store.accessExpiresAt == nil)
    }

    private struct NeverCalledAuth: AccountAuthServing {
        func register(email: String, password: String, name: String) async throws -> AuthSession {
            throw AuthAPIError.invalidResponse
        }
        func signIn(email: String, password: String) async throws -> AuthSession {
            throw AuthAPIError.invalidResponse
        }
        func deleteAccount(accessToken: String) async throws {}
    }
}
