import Foundation

/// Per-notification-type toggles, persisted locally, sent as `preferences`
/// on `POST /devices` (bamware-ios#6). Apps declare the set of types they
/// care about (`knownTypes`, e.g. `["matches", "messages", "digest"]`);
/// every type defaults to enabled until the app turns it off.
///
/// `@unchecked Sendable`: the only stored state is a `UserDefaults`
/// instance, which Apple documents as safe to use from multiple threads —
/// same assumption `KeychainSessionStore`/`AccountSessionStore` make about
/// their own system-framework backing stores.
public struct PushSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String

    /// The full set of preference types this app supports. Used to fill in
    /// defaults for `preferences()` and to validate `setEnabled(_:for:)`
    /// call sites during development — not enforced at runtime beyond that.
    public let knownTypes: [String]

    public init(
        knownTypes: [String],
        defaults: UserDefaults = .standard,
        storageKey: String = "com.bamware.push.preferences"
    ) {
        self.knownTypes = knownTypes
        self.defaults = defaults
        self.storageKey = storageKey
    }

    /// Whether `type` is enabled. Defaults to `true` (opt-out, not opt-in)
    /// for any type not yet explicitly toggled.
    public func isEnabled(_ type: String) -> Bool {
        stored()[type] ?? true
    }

    public func setEnabled(_ enabled: Bool, for type: String) {
        var current = stored()
        current[type] = enabled
        defaults.set(current, forKey: storageKey)
    }

    /// The full map for every `knownTypes` entry, defaults filled in — this
    /// is what `PushRegistrar` sends as `preferences` on register.
    public func preferences() -> [String: Bool] {
        let current = stored()
        var result: [String: Bool] = [:]
        for type in knownTypes {
            result[type] = current[type] ?? true
        }
        return result
    }

    private func stored() -> [String: Bool] {
        defaults.dictionary(forKey: storageKey) as? [String: Bool] ?? [:]
    }
}
