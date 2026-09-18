import Foundation
import BamwareAccounts

// APNs registration + device client (ADR 0001, bamware-ios#6). Every wire
// call this package makes needs a bearer token; that token comes from
// `BamwareAccounts`, never from a constant or from this package reaching
// into the keychain itself.

/// Seam for producing a bearer token for `POST /devices` / `DELETE
/// /devices/:deviceId`. `SessionRefresher` (bamware-ios#3, already merged
/// on `main`) conforms below — its `validAccessToken()` already matches
/// this signature exactly, so no adapter code is needed, only the
/// declaration (same pattern `AccountRefreshing` uses for `AuthAPI`).
public protocol PushBearerProviding: Sendable {
    func validAccessToken() async throws -> String
}

/// Primary wiring: `SessionRefresher.validAccessToken()` — proactively
/// refreshes an expiring access token before handing it back, so a
/// device-token upload triggered in the background doesn't race a stale
/// token.
extension SessionRefresher: PushBearerProviding {}

/// Thrown by `AccountSessionStoreBearerProvider` when there is no signed-in
/// session to read a token from.
public enum PushBearerError: Error, Equatable, Sendable {
    case notSignedIn
}

/// Fallback wiring for an app that has not wired `SessionRefresher` yet
/// (bamware-ios#6: "`validAccessToken()` from B6 if merged, else the
/// current access token"). Reads whatever access token is currently stored
/// without attempting a refresh — good enough for a foreground upload, but
/// callers that want the proactive-refresh behavior should prefer
/// `SessionRefresher`.
public struct AccountSessionStoreBearerProvider: PushBearerProviding {
    private let sessions: AccountSessionStore

    public init(sessions: AccountSessionStore) {
        self.sessions = sessions
    }

    public func validAccessToken() async throws -> String {
        guard let token = sessions.session?.accessToken else { throw PushBearerError.notSignedIn }
        return token
    }
}

/// Deterministic double for tests: script a token, or leave it unset to
/// exercise the "no bearer → no upload" path.
public actor FakePushBearerProvider: PushBearerProviding {
    public enum Failure: Error, Sendable { case notSignedIn }

    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    public func validAccessToken() async throws -> String {
        guard let token else { throw Failure.notSignedIn }
        return token
    }
}
