//
//  AuthServiceTests.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//
import XCTest
@testable import BamwareCore

final class AuthServiceTests: XCTestCase {
    func test_validateToken_setsCurrentUser_withRoles() async throws {
        let sut = MockAuthService()
        let token = "mock-token"
        
        try await sut.validateToken(token)
        
        XCTAssertNotNil(sut.currentUser)
        XCTAssertEqual(sut.currentUser?.tenantID, "bamSocial")
        XCTAssertTrue(sut.currentUser?.roles.contains("bamSocial:canMessage") == true)
    }
    
    func test_validateToken_invalidToken_setsNil() async throws {
        let sut = MockAuthService()
        let token = "invalid-token"
        
        try await sut.validateToken(token)
        
        XCTAssertNil(sut.currentUser)
    }
}

private class MockAuthService: AuthService {
    private(set) var currentUser: User?
    
    func validateToken(_ token: String) async throws {
        if token == "mock-token" {
            currentUser = User(id: "1", tenantID: "bamSocial", roles: ["bamSocial:canMessage"])
        } else {
            currentUser = nil
        }
    }
}
