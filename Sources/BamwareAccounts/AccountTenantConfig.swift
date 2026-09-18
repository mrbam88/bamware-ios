import Foundation

/// Everything about a consuming app's tenant that `BamwareAccounts` needs to
/// talk to the shared auth service and store a session on-device. Apps
/// construct one value and pass it through; the package holds no tenant
/// constants and no environment branching of its own (bamware-ios#2).
public struct AccountTenantConfig: Sendable {
    /// The tenant id the auth service partitions users by. A typo silently
    /// creates a fresh, empty tenant partition, so apps should pin this
    /// value in their own tests.
    public let tenantId: String

    /// Base URL of the auth service for this environment. The app decides
    /// debug vs. release vs. staging; this package never branches on
    /// `#if DEBUG` to pick a host.
    public let authBaseURL: URL

    /// Keychain `kSecAttrService` value `KeychainSessionStore` scopes
    /// persisted sessions under. Should be unique per app (e.g. a reverse-DNS
    /// bundle-style string) so two tenant apps on the same device never
    /// collide.
    public let keychainService: String

    /// Whether this tenant's auth service tenant entry has Sign in with
    /// Apple enabled. Consumed by future UI (BamwareAccountUI, B7/B8) to
    /// decide which provider buttons to show; unused by this package's
    /// session/account logic today.
    public let supportsApple: Bool

    /// Same as `supportsApple`, for Google sign-in.
    public let supportsGoogle: Bool

    public init(
        tenantId: String,
        authBaseURL: URL,
        keychainService: String,
        supportsApple: Bool = false,
        supportsGoogle: Bool = false
    ) {
        self.tenantId = tenantId
        self.authBaseURL = authBaseURL
        self.keychainService = keychainService
        self.supportsApple = supportsApple
        self.supportsGoogle = supportsGoogle
    }
}
