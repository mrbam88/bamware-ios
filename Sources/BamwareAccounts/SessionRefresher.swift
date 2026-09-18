import Foundation

// Silent refresh (ADR 0001, bamware-ios#3). Exchanges the stored refresh
// token before the access token expires, so a signed-in user stays signed in
// for days instead of the access token's 15-minute lifetime, and signs out
// only when the server actually revokes the session.
//
// `AuthContract.swift` (the `AccountAuthServing` seam) is out of this
// ticket's scope, so refresh gets its own narrow seam (`AccountRefreshing`)
// rather than growing that protocol.

/// Seam for the refresh call. `AuthAPI` conforms below; tests use a fake.
public protocol AccountRefreshing: Sendable {
    /// Exchanges a refresh token for a new access + refresh pair per the
    /// auth-service A2 contract (`POST /auth/refresh`, rotating: the
    /// presented refresh token is single-use). Any 401 — including
    /// `refresh_reused` — surfaces as `AuthAPIError.http(statusCode: 401)`.
    func refresh(refreshToken: String) async throws -> AuthSession
}

extension AuthAPI: AccountRefreshing {}

/// A clock seam so refresh timing is testable without wall-clock sleeps.
public protocol RefreshClock: Sendable {
    func now() -> Date
}

public struct SystemRefreshClock: RefreshClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Why `SessionRefresher` decided the session is over — not a transient
/// network failure. UI-facing copy is `AccountModel`'s job.
public enum SessionEndReason: Equatable, Sendable {
    /// The server rejected the refresh token outright: expired, reused
    /// (`refresh_reused`), or otherwise invalid. Any 401 from
    /// `POST /auth/refresh` maps here — the auth-service A2 contract does
    /// not require clients to distinguish the specific reason.
    case refreshRejected
}

/// Thrown by `SessionRefresher` when it cannot produce a valid access token.
public enum SessionRefresherError: Error, Equatable, Sendable {
    /// `validAccessToken()`/`refreshAfterUnauthorized()` called with no
    /// stored session — a usage error, not a server revoke.
    case notSignedIn
    /// The server ended the session (see `SessionEndReason`). The session
    /// has already been cleared from `AccountSessionStore` by the time this
    /// throws; callers wire this to `AccountModel.signOutOnSessionEnd(reason:)`
    /// (see the package README) to surface it in UI.
    case sessionEnded(reason: SessionEndReason)
}

/// Decodes the standard `exp` claim (seconds since epoch) from a JWT's
/// payload segment — no third-party library, just base64url + `JSONDecoder`.
enum JWTExpiry {
    private struct Payload: Decodable { let exp: Double }

    static func expiresAt(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, let data = base64URLDecode(String(segments[1])) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return Date(timeIntervalSince1970: payload.exp)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64.append(String(repeating: "=", count: 4 - remainder)) }
        return Data(base64Encoded: base64)
    }
}

/// Refreshes the access token before it expires (or on demand after a 401),
/// single-flight so concurrent callers await one in-flight refresh instead
/// of racing the auth service (which would rotate the refresh token out from
/// under a second caller). Actor-isolated for exactly that reason.
///
/// Apps wire this in front of their own API clients:
/// `let token = try await refresher.validAccessToken()`. See the package
/// README for the full pattern, including how a `SessionRefresherError
/// .sessionEnded` propagates to `AccountModel`.
public actor SessionRefresher {
    /// Refresh proactively once fewer than this much time remains on the
    /// access token (per the ticket: "< 2 min left").
    public static let proactiveWindow: TimeInterval = 120

    private let refreshing: any AccountRefreshing
    private let sessions: AccountSessionStore
    private let clock: any RefreshClock

    private var inFlight: Task<AuthSession, Error>?

    public init(
        refreshing: any AccountRefreshing,
        sessions: AccountSessionStore,
        clock: any RefreshClock = SystemRefreshClock()
    ) {
        self.refreshing = refreshing
        self.sessions = sessions
        self.clock = clock
    }

    /// A request-authorizing hook: returns an access token good for at least
    /// `proactiveWindow`, refreshing first if the stored one is not.
    public func validAccessToken() async throws -> String {
        guard sessions.session != nil else { throw SessionRefresherError.notSignedIn }
        if let expiresAt = sessions.accessExpiresAt,
           expiresAt.timeIntervalSince(clock.now()) > Self.proactiveWindow {
            return sessions.session!.accessToken
        }
        return try await performRefresh().accessToken
    }

    /// For an app's API client to call after a request comes back 401:
    /// forces one refresh (bypassing the proactive-window check, since the
    /// access token's own `exp` said it should still be valid) and returns
    /// the new token for a single retry. A second 401 after that retry is
    /// the caller's own job to treat as failure — this method does not loop.
    public func refreshAfterUnauthorized() async throws -> String {
        try await performRefresh().accessToken
    }

    // MARK: - Single-flight core

    private func performRefresh() async throws -> AuthSession {
        if let inFlight {
            return try await inFlight.value
        }
        guard let current = sessions.session else { throw SessionRefresherError.notSignedIn }

        let refreshing = self.refreshing
        let task = Task<AuthSession, Error> {
            try await refreshing.refresh(refreshToken: current.refreshToken)
        }
        inFlight = task
        defer { inFlight = nil }

        do {
            let refreshed = try await task.value
            sessions.store(refreshed)
            return refreshed
        } catch AuthAPIError.http(statusCode: 401) {
            // Reuse or expiry — auth-service A2: any 401 from /auth/refresh
            // means the session is over, not "try again".
            sessions.clear()
            throw SessionRefresherError.sessionEnded(reason: .refreshRejected)
        }
    }
}
