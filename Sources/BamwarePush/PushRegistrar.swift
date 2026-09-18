import Foundation

/// Orchestrates APNs registration end to end (bamware-ios#6): permission →
/// `registerForRemoteNotifications()` → upload the resulting device token
/// to the push service with a bearer from `BamwareAccounts` → delete on
/// sign-out. An actor, so concurrent calls (e.g. a token refresh callback
/// racing a manual re-register) serialize instead of interleaving two
/// uploads.
///
/// Every dependency is injected as a protocol, so tests build a
/// `PushRegistrar` entirely out of fakes (`FakePushPermissionRequester`,
/// `FakeRemoteNotificationRegistrar`, `FakePushDeviceClient`,
/// `FakePushBearerProvider`) and never touch `UNUserNotificationCenter`,
/// `UIApplication`, the network, or the keychain.
public actor PushRegistrar {
    public struct Configuration: Sendable {
        /// See `PushDeviceIdentity.current()` for the default, persisted
        /// generator; tests pass a fixed id.
        public let deviceId: String
        public let platform: String

        public init(deviceId: String, platform: String = "ios") {
            self.deviceId = deviceId
            self.platform = platform
        }
    }

    private let configuration: Configuration
    private let permissions: any PushPermissionRequesting
    private let remoteRegistrar: any RemoteNotificationRegistering
    private let deviceClient: any PushDeviceRegistering
    private let bearer: any PushBearerProviding
    private let settings: PushSettings

    public init(
        configuration: Configuration,
        permissions: any PushPermissionRequesting,
        remoteRegistrar: any RemoteNotificationRegistering,
        deviceClient: any PushDeviceRegistering,
        bearer: any PushBearerProviding,
        settings: PushSettings
    ) {
        self.configuration = configuration
        self.permissions = permissions
        self.remoteRegistrar = remoteRegistrar
        self.deviceClient = deviceClient
        self.bearer = bearer
        self.settings = settings
    }

    /// Requests permission and, if granted, calls
    /// `registerForRemoteNotifications()`. Reuses BrewDesk's prompt policy
    /// (`VisitReminderScheduling`): only actually prompts when the status is
    /// `.notDetermined`; an already-`.denied` status returns `false` without
    /// re-prompting; a UI already showing "Enable in Settings" copy owns
    /// that case, not another system prompt. Call this from the app's own
    /// permission moment — not automatically at launch.
    @discardableResult
    public func requestPermissionAndRegister() async -> Bool {
        let granted: Bool
        switch await permissions.currentAuthorizationStatus() {
        case .authorized:
            granted = true
        case .denied:
            granted = false
        case .notDetermined:
            granted = await permissions.requestAuthorization()
        }
        guard granted else { return false }
        await remoteRegistrar.registerForRemoteNotifications()
        return true
    }

    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// with the raw token `Data` APNs hands the app. Converts to the hex
    /// string form the push service expects and uploads it. Calling this
    /// again with a different token (APNs occasionally rotates it) re-runs
    /// the upload — no dedup against the previous token, since a changed
    /// token means the old one is no longer valid to send to.
    public func didReceiveDeviceToken(_ tokenData: Data) async {
        await upload(token: Self.hex(tokenData))
    }

    /// Same as above, for callers (tests, or an app already holding a
    /// hex-encoded token) that don't have raw `Data`.
    public func didReceiveDeviceToken(hex token: String) async {
        await upload(token: token)
    }

    /// Call before clearing the local session on sign-out — while the
    /// bearer is still valid, since `AccountSessionStore.clear()` (or
    /// `AccountModel.signOut()`, which calls it) removes the very token
    /// this needs. A signed-out state (no bearer) makes this a no-op rather
    /// than an error: there's nothing left to authenticate the delete with,
    /// and an orphaned device row is harmless (bamware-infra#8 is Bearer
    /// auth only — no unauthenticated delete path to fall back to).
    public func deleteOnSignOut() async {
        guard let bearerToken = try? await bearer.validAccessToken() else { return }
        try? await deviceClient.deleteDevice(deviceId: configuration.deviceId, bearerToken: bearerToken)
    }

    private func upload(token: String) async {
        // No bearer → no upload: an unauthenticated app (never signed in,
        // or signed out) has nothing to authenticate the request with, and
        // bamware-infra#8's `/devices` endpoints are Bearer-only.
        guard let bearerToken = try? await bearer.validAccessToken() else { return }
        try? await deviceClient.register(
            deviceId: configuration.deviceId,
            token: token,
            platform: configuration.platform,
            preferences: settings.preferences(),
            bearerToken: bearerToken
        )
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
