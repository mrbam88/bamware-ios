#if DEBUG
import Foundation
import Testing
@testable import BamwareCore

enum FixtureEnvironment: String, DebugBackendEnvironment {
    case localhost, stage, production

    var baseURL: URL {
        switch self {
        case .localhost: URL(string: "http://localhost:3000")!
        case .stage: URL(string: "https://stage.example.com")!
        case .production: URL(string: "https://api.example.com")!
        }
    }
}

@Suite @MainActor struct DebugEnvironmentStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "debug-env-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsToProvidedEnvironment() {
        let store = DebugEnvironmentStore(default: FixtureEnvironment.localhost, defaults: freshDefaults())
        #expect(store.current == .localhost)
    }

    @Test func selectionPersistsAcrossStoreInstances() {
        let defaults = freshDefaults()
        let first = DebugEnvironmentStore(default: FixtureEnvironment.localhost, defaults: defaults)
        first.current = .stage
        let second = DebugEnvironmentStore(default: FixtureEnvironment.localhost, defaults: defaults)
        #expect(second.current == .stage)
    }

    @Test func unknownPersistedValueFallsBackToDefault() {
        let defaults = freshDefaults()
        defaults.set("deleted-env", forKey: "bamware.debug.environment")
        let store = DebugEnvironmentStore(default: FixtureEnvironment.production, defaults: defaults)
        #expect(store.current == .production)
    }
}
#endif
