import Foundation
import UserNotifications

// Permission prompt policy reused from BrewDesk's `VisitReminderScheduling`
// (`bamware-brewdesk/Packages/BrewDeskKit/Sources/BrewDeskKit/VisitReminderScheduling.swift`):
// a three-state status the caller can act on (`.denied` means "show Enable
// in Settings", never re-prompt) instead of a raw `UNAuthorizationStatus`,
// and a deterministic fake so tests never trigger a real system prompt.
// `UserNotifications` is available on both iOS and macOS 14+, so nothing
// here needs an `#if os(iOS)` guard — only `RemoteNotificationRegistering`
// (UIKit-only) does.

/// Mirrors the subset of `UNAuthorizationStatus` callers need.
public enum PushAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// The permission-prompt capability. `SystemPushPermissionRequester` is the
/// real `UNUserNotificationCenter`-backed implementation;
/// `FakePushPermissionRequester` is the deterministic test double.
public protocol PushPermissionRequesting: Sendable {
    func currentAuthorizationStatus() async -> PushAuthorizationStatus
    @discardableResult
    func requestAuthorization() async -> Bool
}

/// `@unchecked Sendable`: `UNUserNotificationCenter` is a thread-safe
/// singleton-style class (same assumption `BrewDeskKit`'s
/// `UserNotificationVisitReminders` makes), not one the SDK's public
/// interface itself declares `Sendable`.
public final class SystemPushPermissionRequester: PushPermissionRequesting, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func currentAuthorizationStatus() async -> PushAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// Deterministic double: records call count, scripts the grant result,
/// never touches `UNUserNotificationCenter`.
public actor FakePushPermissionRequester: PushPermissionRequesting {
    private var authorizationGrantResult: Bool
    public private(set) var authorizationStatus: PushAuthorizationStatus = .notDetermined
    public private(set) var requestCount = 0

    public init(authorizationGrantResult: Bool = true) {
        self.authorizationGrantResult = authorizationGrantResult
    }

    /// Scripts both the next `requestAuthorization()` result and the status
    /// `currentAuthorizationStatus()` reports before any request is made.
    public func setGrantResult(_ granted: Bool) {
        authorizationGrantResult = granted
    }

    /// Sets the status directly (e.g. simulate an already-determined status
    /// from a previous launch, without going through `requestAuthorization`).
    public func setAuthorizationStatus(_ status: PushAuthorizationStatus) {
        authorizationStatus = status
    }

    public func currentAuthorizationStatus() async -> PushAuthorizationStatus {
        authorizationStatus
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        requestCount += 1
        authorizationStatus = authorizationGrantResult ? .authorized : .denied
        return authorizationGrantResult
    }
}
