import SwiftUI
import BamwareCore
import BamwareUI

public struct MessageListView: View {
    public let messages: [Message]
    private let theme: any Theme
    private let authService: AuthService  // Pass—core no Factory
    
    public var shouldShowMessages: Bool {
        guard let user = authService.currentUser,
              let tenantID = messages.first?.tenantID,
              user.tenantID == tenantID else { return false }
        return user.roles.contains("\(tenantID):canMessage")
    }
    
    public init(messages: [Message] = [], tenantID: String = "demoTenant", isDarkMode: Bool = false, authService: AuthService) {
        self.messages = messages
        self.theme = BrandingPalette.theme(for: tenantID, isDarkMode: isDarkMode)
        self.authService = authService
    }
    
    public var body: some View {
        if shouldShowMessages {
            List(messages, id: \.id) { message in
                SmartText(message.content, theme: theme)
            }
            .navigationTitle("Messages")
            .background(theme.backgroundColor)
        } else {
            Text("No permission to view messages")
                .foregroundColor(theme.secondaryColor)
                .background(theme.backgroundColor)
        }
    }
}
