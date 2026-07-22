import SwiftUI
import BamwareCore
import BamwareUI

public struct MessageListView: View {
    public let messages: [Message]
    public let tenantID: String
    public let isDarkMode: Bool
    private let authService: AuthService

    public var theme: any Theme {
        BrandingPalette.theme(for: tenantID, isDarkMode: isDarkMode)
    }

    public var shouldShowMessages: Bool {
        guard let user = authService.currentUser,
              let messageTenantID = messages.first?.tenantID,
              user.tenantID == messageTenantID else { return false }
        return user.roles.contains("\(messageTenantID):canMessage")
    }

    public init(
        messages: [Message] = [],
        tenantID: String = "demoTenant",
        isDarkMode: Bool = false,
        authService: AuthService
    ) {
        self.messages = messages
        self.tenantID = tenantID
        self.isDarkMode = isDarkMode
        self.authService = authService
    }

    public var body: some View {
        Group {
            if shouldShowMessages {
                List(messages, id: \.id) { message in
                    SmartText(message.content, theme: theme)
                        .listRowBackground(theme.backgroundColor)
                }
                .scrollContentBackground(.hidden)
                .background(theme.backgroundColor)
                .navigationTitle("Messages")
            } else {
                Text("No permission to view messages")
                    .foregroundColor(theme.secondaryColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.backgroundColor)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDarkMode)
    }
}
