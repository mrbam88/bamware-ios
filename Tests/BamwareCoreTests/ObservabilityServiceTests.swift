//
//  ObservabilityServiceTests.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//
import XCTest
@testable import BamwareCore

final class ObservabilityServiceTests: XCTestCase {
    func test_log_recordsTenantTaggedMessage() {
        let sut = MockObservabilityService()
        let metadata = ObservabilityMetadata(tenantID: "bamSocial")
        
        sut.log("Login attempt", level: .info, metadata: metadata)
        
        XCTAssertEqual(sut.loggedMessages.count, 1)
        XCTAssertEqual(sut.loggedMessages[0], "[bamSocial] Login attempt")
    }
}

private class MockObservabilityService: ObservabilityService {
    var loggedMessages: [String] = []
    
    func log(_ message: String, level: LogLevel, metadata: ObservabilityMetadata) {
        loggedMessages.append("[\(metadata.tenantID)] \(message)")
    }
}
