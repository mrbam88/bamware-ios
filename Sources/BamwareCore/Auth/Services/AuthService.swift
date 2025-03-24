
public protocol AuthService {
    var currentUser: User? { get }
    func validateToken(_ token: String) async throws
    func setPermissionsService(_ service: UserPermissionsService)
}
