#if DEBUG
import Foundation
import Observation

/// Bamware debug environment switching — the model half.
///
/// Everything in this file (and its BamwareUI counterpart) compiles ONLY in
/// Debug configurations: App Store binaries contain none of it, so there is
/// no hidden-feature review surface (Apple Guideline 2.3.1).
///
/// An app adopts it by declaring one enum:
///
///     enum AppEnvironment: String, DebugBackendEnvironment {
///         case localhost, stage, production
///         var baseURL: URL { ... }
///     }
///
/// and holding a `DebugEnvironmentStore<AppEnvironment>`.
public protocol DebugBackendEnvironment: CaseIterable, Identifiable, Hashable,
    RawRepresentable<String>, Sendable {
    var baseURL: URL { get }
    /// The environment real users are on — the badge hides when current.
    static var production: Self { get }
}

extension DebugBackendEnvironment {
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// UserDefaults-persisted selection, namespaced per app by `key`.
@MainActor
@Observable
public final class DebugEnvironmentStore<Env: DebugBackendEnvironment> {
    private let key: String
    private let defaults: UserDefaults

    public var current: Env {
        didSet { defaults.set(current.rawValue, forKey: key) }
    }

    public init(
        default defaultEnv: Env,
        key: String = "bamware.debug.environment",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
        self.current = defaults.string(forKey: key)
            .flatMap(Env.init(rawValue:)) ?? defaultEnv
    }
}
#endif
