// MessageListView.swift (Body unchanged—Preview tweaked)
import SwiftUI
import BamwareCore
import BamwareUI

public struct MessageListView: View {
    private let messages: [Message]
    private let theme: any Theme
    
    public init(messages: [Message] = [], tenantID: String = "bamSocial", isDarkMode: Bool = false) {
        self.messages = messages
        self.theme = BrandingPalette.theme(for: tenantID, isDarkMode: isDarkMode)
    }
    
    public var body: some View {
        List(messages, id: \.id) { message in
            SmartText(message.content, theme: theme)
        }
        .navigationTitle("Messages")
        .background(theme.backgroundColor)
    }
}

struct MessageListView_Previews: PreviewProvider {
    static let mockMessages = [
        Message(id: "1", content: "Yo, brah!", tenantID: "bamSocial"),
        Message(id: "2", content: "Bamware’s live!", tenantID: "bamSocial")
    ]
    
    static let mockMatchMessages = [
        Message(id: "1", content: "Hey, cutie!", tenantID: "bamMatch"),
        Message(id: "2", content: "Match me!", tenantID: "bamMatch")
    ]
    
    static var previews: some View {
        Group {
            MessageListView(messages: mockMessages, tenantID: "bamSocial", isDarkMode: false)
                .previewDisplayName("bamSocial Light")
            
            MessageListView(messages: mockMessages, tenantID: "bamSocial", isDarkMode: true)
                .previewDisplayName("bamSocial Dark")
            
            MessageListView(messages: mockMatchMessages, tenantID: "bamMatch", isDarkMode: false)
                .previewDisplayName("bamMatch Light")
            
            MessageListView(messages: mockMatchMessages, tenantID: "bamMatch", isDarkMode: true)
                .previewDisplayName("bamMatch Dark")
        }
        .previewLayout(.sizeThatFits)
    }
}
