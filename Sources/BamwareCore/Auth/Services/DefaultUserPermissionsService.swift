// DefaultUserPermissionsService.swift
public class DefaultUserPermissionsService: UserPermissionsService {
    private let authService: AuthService
    
    public init(authService: AuthService) {
        self.authService = authService
    }
    
    public func hasPermission(_ permission: String, tenantID: String) -> Bool {
        guard let user = authService.currentUser, user.tenantID == tenantID else { return false }
        return user.roles.contains("\(tenantID):\(permission)")
    }
}
