import Combine

public class DefaultAuthService: AuthService, ObservableObject {
    @Published public var currentUser: User?
    private var permissionsService: UserPermissionsService?
    
    public init() {}
    
    public func setPermissionsService(_ service: UserPermissionsService) {
        self.permissionsService = service
    }
    
    @MainActor  // Main—method-only
    public func validateToken(_ token: String) async throws {
        if token == "mock-token" {
            currentUser = User(id: "1", tenantID: "demoTenant", roles: ["demoTenant:canMessage"])
        } else {
            currentUser = nil
        }
    }
}
