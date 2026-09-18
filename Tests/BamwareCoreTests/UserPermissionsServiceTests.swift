// UserPermissionsServiceTests.swift
import XCTest
@testable import BamwareCore

final class UserPermissionsServiceTests: XCTestCase {
    func test_hasPermission_returnsTrueForRole() {
        let user = User(id: "1", tenantID: "bamSocial", roles: ["bamSocial:canMessage"])
        let authService = MockAuthService(currentUser: user)
        let sut = DefaultUserPermissionsService(authService: authService)
        
        let hasPerm = sut.hasPermission("canMessage", tenantID: "bamSocial")
        
        XCTAssertTrue(hasPerm)
    }
    
    func test_hasPermission_returnsFalseForMissingRole() {
        let user = User(id: "1", tenantID: "bamSocial", roles: ["bamSocial:canView"])
        let authService = MockAuthService(currentUser: user)
        let sut = DefaultUserPermissionsService(authService: authService)
        
        let hasPerm = sut.hasPermission("canMessage", tenantID: "bamSocial")
        
        XCTAssertFalse(hasPerm)
    }
    
    func test_hasPermission_noUser_returnsFalse() {
        let authService = MockAuthService(currentUser: nil)
        let sut = DefaultUserPermissionsService(authService: authService)
        
        let hasPerm = sut.hasPermission("canMessage", tenantID: "bamSocial")
        
        XCTAssertFalse(hasPerm)
    }
}

private class MockAuthService: AuthService {
    fileprivate let currentUser: User?
    
    init(currentUser: User?) {
        self.currentUser = currentUser
    }
    
    func setPermissionsService(_ service: UserPermissionsService) {
        // No-op — mock only (protocol gained this requirement after the mock was written)
    }

    func validateToken(_ token: String) async throws {
        // No-op—mock only
    }
}
