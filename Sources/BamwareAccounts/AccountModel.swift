// Shared account state machine (ADR 0001). Sign in / sign up / sign out plus
// the ordered account deletion pattern (content → auth record → local
// session).
import Foundation
import Observation
import SwiftUI

/// Drives account screens. All transition rules live here so they are
/// unit-testable without UI.
@Observable
public final class AccountModel {
    public enum Phase: Equatable {
        case idle
        case working
        /// `message` is the friendly, user-facing sentence — never a raw error.
        case failed(message: String)
    }

    /// Outcome of the ordered deletion — drives the deletion screen's copy.
    public enum DeletionOutcome: Equatable {
        /// Everything gone, signed out.
        case completed
        /// Step 1 (content) failed: the session is INTACT — plain retry.
        case contentFailed(message: String)
        /// Content gone but the auth record may remain. Local session is
        /// cleared (the account is unusable); both endpoints treat "already
        /// gone" as success, so sign-in-and-retry completes the job.
        case authIncomplete
    }

    public private(set) var phase: Phase = .idle
    public let sessions: AccountSessionStore

    private let auth: any AccountAuthServing
    private let content: any AccountContentDeleting

    public init(
        auth: any AccountAuthServing,
        content: any AccountContentDeleting = NoUserContentService(),
        sessions: AccountSessionStore
    ) {
        self.auth = auth
        self.content = content
        self.sessions = sessions
    }

    public var isWorking: Bool { phase == .working }

    // MARK: - Sign in / up / out

    public func signIn(email: String, password: String) async {
        await run { try await self.auth.signIn(email: email, password: password) }
    }

    public func signUp(email: String, password: String, name: String) async {
        await run { try await self.auth.register(email: email, password: password, name: name) }
    }

    public func signOut() {
        sessions.clear()
        phase = .idle
    }

    /// The signed-out-on-revoke transition (bamware-ios#3): call this from
    /// wherever an app catches `SessionRefresherError.sessionEnded` (see
    /// `SessionRefresher` and the package README) so a server-side revoke
    /// surfaces as a distinguishable "you were signed out" message rather
    /// than a silently cleared session. `SessionRefresher` has already
    /// cleared the session by the time this throws; this just puts the
    /// reason in front of the UI.
    public func signOutOnSessionEnd(reason: SessionEndReason) {
        sessions.clear()
        phase = .failed(message: Self.sessionEndedMessage(for: reason))
    }

    private func run(_ operation: @escaping () async throws -> AuthSession) async {
        guard phase != .working else { return }
        phase = .working
        do {
            let session = try await operation()
            sessions.store(session)
            phase = .idle
        } catch {
            phase = .failed(message: Self.friendlyMessage(for: error))
        }
    }

    // MARK: - Ordered account deletion

    /// Order matters: app content first, then the auth record (deleting it
    /// breaks refresh/re-login — so it must go last, and before local tokens
    /// are cleared). Both server calls treat "already gone" as success, so
    /// the whole flow is safe to re-run after a partial failure.
    public func deleteAccount() async -> DeletionOutcome {
        guard let session = sessions.session else { return .completed }
        phase = .working
        defer { if phase == .working { phase = .idle } }

        // 1. App content. Failure here leaves the session intact — plain retry.
        do {
            try await content.deleteUserContent(accessToken: session.accessToken)
        } catch {
            let outcome = DeletionOutcome.contentFailed(
                message: "Couldn't delete your account right now. Check your connection and try again."
            )
            phase = .idle
            return outcome
        }

        // 2. Auth record — revokes refresh/re-login, so it goes last.
        do {
            try await auth.deleteAccount(accessToken: session.accessToken)
        } catch {
            // Content is gone; the account is unusable either way — clear the
            // local session, surface the incomplete state.
            sessions.clear()
            phase = .idle
            return .authIncomplete
        }

        // 3. Local session — only after both network steps.
        sessions.clear()
        phase = .idle
        return .completed
    }

    // MARK: - Copy

    /// Friendly copy only — raw errors and status codes never reach the UI.
    static func friendlyMessage(for error: Error) -> String {
        if let authError = error as? AuthAPIError,
           let description = authError.errorDescription {
            return description
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            return "You look offline. Try again in a moment."
        }
        return "Couldn't reach the account service. Try again in a moment."
    }

    /// Friendly copy for `signOutOnSessionEnd`. One reason today
    /// (`.refreshRejected`); a `switch` (not `if`) so a future
    /// `SessionEndReason` case fails to compile here instead of silently
    /// reusing the wrong message.
    static func sessionEndedMessage(for reason: SessionEndReason) -> String {
        switch reason {
        case .refreshRejected:
            "You were signed out because this session ended. Sign in again to continue."
        }
    }
}

// MARK: - Service injection

/// Optional-first auth service injection: screens read it from the
/// environment; nil (the default) means the screen resolves its own
/// `AccountAuthServing` at the app's composition root. Resolved screen-side
/// so the feature stays additive to whatever composes the app.
private struct AccountAuthServiceKey: EnvironmentKey {
    static let defaultValue: (any AccountAuthServing)? = nil
}

extension EnvironmentValues {
    public var accountAuthService: (any AccountAuthServing)? {
        get { self[AccountAuthServiceKey.self] }
        set { self[AccountAuthServiceKey.self] = newValue }
    }
}
