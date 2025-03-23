// DefaultAuthService.swift
import Combine

public class DefaultAuthService: AuthService {
    @Published public var currentUser: User?  // Drop private(set)—public matches protocol
    private let permissionsService: UserPermissionsService
    
    public init(permissionsService: UserPermissionsService) {
        self.permissionsService = permissionsService
    }
    
    public func validateToken(_ token: String) async throws {
        if token == "mock-token" {
            currentUser = User(id: "1", tenantID: "demoTenant", roles: ["demoTenant:canMessage"])
        } else {
            currentUser = nil
        }
    }
}
