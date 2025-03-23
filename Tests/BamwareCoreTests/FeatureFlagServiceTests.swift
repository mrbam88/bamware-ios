//
//  FeatureFlagServiceTests.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//

import XCTest
@testable import BamwareCore

final class FeatureFlagServiceTests: XCTestCase {
    func test_isEnabled_returnsTrueForEnabledFeature() {
        let sut = MockFeatureFlagService(enabledFeatures: ["messaging"])
        let isEnabled = sut.isEnabled("messaging", tenantID: "bamSocial")
        
        XCTAssertTrue(isEnabled)
    }
    
    func test_isEnabled_returnsFalseForDisabledFeature() {
        let sut = MockFeatureFlagService(enabledFeatures: ["profile"])
        let isEnabled = sut.isEnabled("messaging", tenantID: "bamSocial")
        
        XCTAssertFalse(isEnabled)
    }
}

private class MockFeatureFlagService: FeatureFlagService {
    private let enabledFeatures: [String]
    
    init(enabledFeatures: [String] = []) {
        self.enabledFeatures = enabledFeatures
    }
    
    func isEnabled(_ feature: String, tenantID: String) -> Bool {
        enabledFeatures.contains(feature)
    }
}
