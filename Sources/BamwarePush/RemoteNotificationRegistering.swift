import Foundation
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

// `UIApplication.registerForRemoteNotifications()` is UIKit/iOS-only.
// House rule: guard it with `#if os(iOS)`/`canImport(UIKit)` so the macOS
// host gate (`swift test`, run on the dev machine) still compiles — the
// real implementation only builds in the iOS-simulator `xcodebuild` gate.
// `PushRegistrar` and its tests only ever see the plain, cross-platform
// protocol below.

/// Seam for the one UIKit call this package needs. Declared as a plain
/// (non-`@MainActor`) `async` requirement so a `@MainActor`-isolated
/// implementation can satisfy it (calling into MainActor from `async`
/// context is just an `await`), while the fake used in tests needs no
/// main-thread hop at all.
public protocol RemoteNotificationRegistering: Sendable {
    func registerForRemoteNotifications() async
}

#if canImport(UIKit) && os(iOS)
/// Real implementation: `UIApplication.shared.registerForRemoteNotifications()`,
/// which must run on the main thread.
public struct UIKitRemoteNotificationRegistrar: RemoteNotificationRegistering {
    public init() {}

    public func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
#endif

/// Deterministic double for tests: records call count, never touches
/// `UIApplication` (so it compiles and runs on the macOS host gate too).
public actor FakeRemoteNotificationRegistrar: RemoteNotificationRegistering {
    public private(set) var callCount = 0

    public init() {}

    public func registerForRemoteNotifications() async {
        callCount += 1
    }
}
