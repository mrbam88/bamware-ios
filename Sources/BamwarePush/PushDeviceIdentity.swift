import Foundation

/// A stable per-install device id for `POST /devices` / `DELETE
/// /devices/:deviceId`, generated once and persisted in `UserDefaults`
/// (reinstall gets a fresh id and a fresh server-side row, which is fine —
/// the old row is orphaned but harmless, same tradeoff `deviceId` schemes
/// like this always make). Kept separate from `PushRegistrar` so it stays a
/// small, directly testable pure function of a `UserDefaults` instance
/// rather than something `PushRegistrar`'s own tests need to stub.
public enum PushDeviceIdentity {
    private static let key = "com.bamware.push.deviceId"

    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }
}
