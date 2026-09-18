import Foundation
import Testing
@testable import BamwarePush

@Suite struct PushDeviceIdentityTests {
    @Test func generatesAndPersistsAStableId() {
        let defaults = UserDefaults(suiteName: "PushDeviceIdentityTests-\(UUID().uuidString)")!
        let first = PushDeviceIdentity.current(defaults: defaults)
        let second = PushDeviceIdentity.current(defaults: defaults)
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test func differentDefaultsSuitesGetDifferentIds() {
        let a = PushDeviceIdentity.current(defaults: UserDefaults(suiteName: "PushDeviceIdentityTests-a-\(UUID().uuidString)")!)
        let b = PushDeviceIdentity.current(defaults: UserDefaults(suiteName: "PushDeviceIdentityTests-b-\(UUID().uuidString)")!)
        #expect(a != b)
    }
}
