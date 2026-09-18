import Foundation
import Testing
@testable import BamwarePush

@Suite struct PushSettingsTests {
    private func makeSettings(knownTypes: [String] = ["matches", "messages", "digest"]) -> PushSettings {
        PushSettings(
            knownTypes: knownTypes,
            defaults: UserDefaults(suiteName: "PushSettingsTests-\(UUID().uuidString)")!,
            storageKey: "prefs"
        )
    }

    @Test func defaultsEveryTypeToEnabled() {
        let settings = makeSettings()
        #expect(settings.isEnabled("matches"))
        #expect(settings.isEnabled("messages"))
        #expect(settings.preferences() == ["matches": true, "messages": true, "digest": true])
    }

    @Test func setEnabledPersistsAndReflectsInPreferences() {
        let settings = makeSettings()
        settings.setEnabled(false, for: "digest")

        #expect(settings.isEnabled("digest") == false)
        #expect(settings.isEnabled("matches"))
        #expect(settings.preferences() == ["matches": true, "messages": true, "digest": false])
    }

    @Test func persistsAcrossInstancesSharingTheSameDefaults() {
        let defaults = UserDefaults(suiteName: "PushSettingsTests-shared-\(UUID().uuidString)")!
        let first = PushSettings(knownTypes: ["matches"], defaults: defaults, storageKey: "prefs")
        first.setEnabled(false, for: "matches")

        let second = PushSettings(knownTypes: ["matches"], defaults: defaults, storageKey: "prefs")
        #expect(second.isEnabled("matches") == false)
    }
}
