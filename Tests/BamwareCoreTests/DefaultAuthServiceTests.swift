import XCTest
@testable import BamwareCore
import Combine

final class DefaultAuthServiceTests: XCTestCase {
    var permissionsService: MockUserPermissionsService!
    var sut: DefaultAuthService!
    
    override func setUp() {
        super.setUp()
        permissionsService = MockUserPermissionsService()
        sut = DefaultAuthService(permissionsService: permissionsService)
    }
    
    func test_validateToken_withValidToken_setsCurrentUser() async throws {
        let token = "mock-token"
        
        try await sut.validateToken(token)
        
        XCTAssertNotNil(sut.currentUser)
        XCTAssertEqual(sut.currentUser?.id, "1")
        XCTAssertEqual(sut.currentUser?.tenantID, "demoTenant")
        XCTAssertEqual(sut.currentUser?.roles, ["demoTenant:canMessage"])
    }
    
    func test_validateToken_withInvalidToken_setsCurrentUserNil() async throws {
        let token = "invalid-token"
        
        try await sut.validateToken(token)
        
        XCTAssertNil(sut.currentUser)
    }
    
    func test_validateToken_publishesCurrentUserChange() async throws {
        let token = "mock-token"
        var receivedUsers: [User?] = []
        let cancellable = sut.$currentUser.sink { user in
            receivedUsers.append(user)
        }
        
        try await sut.validateToken(token)
        
        XCTAssertEqual(receivedUsers.count, 2)  // Initial nil, then User
        XCTAssertNil(receivedUsers[0])
        XCTAssertEqual(receivedUsers[1]?.tenantID, "demoTenant")
        cancellable.cancel()
    }
}

public class MockUserPermissionsService: UserPermissionsService {
    public func hasPermission(_ permission: String, tenantID: String) -> Bool {
        return true  // Mock—always allow
    }
}
