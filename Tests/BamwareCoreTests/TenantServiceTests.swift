//
//  TenantServiceTests.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//
import XCTest
@testable import BamwareCore

final class TenantServiceTests: XCTestCase {
    func test_currentTenant_returnsTenantWithID() {
        let sut = MockTenantService()
        let tenant = sut.currentTenant()
        
        XCTAssertNotNil(tenant)
        XCTAssertEqual(tenant?.id, "bamSocial")
        XCTAssertEqual(tenant?.tenantID, "bamSocial")
    }
    
    func test_currentTenant_noTenant_returnsNil() {
        let sut = MockTenantService(hasTenant: false)
        let tenant = sut.currentTenant()
        
        XCTAssertNil(tenant)
    }
}

private class MockTenantService: TenantService {
    private let hasTenant: Bool
    
    init(hasTenant: Bool = true) {
        self.hasTenant = hasTenant
    }
    
    func currentTenant() -> Tenant? {
        hasTenant ? Tenant(id: "bamSocial", tenantID: "bamSocial") : nil
    }
}
