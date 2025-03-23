//
//  MessageListView.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/23/25.
//

// MessageListView.swift
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

#Preview("Light Mode - bamSocial") {
    let mockMessages = [
        Message(id: "1", content: "Yo, brah!", tenantID: "bamSocial"),
        Message(id: "2", content: "Bamware’s live!", tenantID: "bamSocial")
    ]
    MessageListView(messages: mockMessages, tenantID: "bamSocial", isDarkMode: false)
}

#Preview("Dark Mode - bamSocial") {
    let mockMessages = [
        Message(id: "1", content: "Yo, brah!", tenantID: "bamSocial"),
        Message(id: "2", content: "Bamware’s live!", tenantID: "bamSocial")
    ]
    MessageListView(messages: mockMessages, tenantID: "bamSocial", isDarkMode: true)
}

#Preview("Light Mode - bamMatch") {
    let mockMessages = [
        Message(id: "1", content: "Hey, cutie!", tenantID: "bamMatch"),
        Message(id: "2", content: "Match me!", tenantID: "bamMatch")
    ]
    MessageListView(messages: mockMessages, tenantID: "bamMatch", isDarkMode: false)
}

#Preview("Dark Mode - bamMatch") {
    let mockMessages = [
        Message(id: "1", content: "Hey, cutie!", tenantID: "bamMatch"),
        Message(id: "2", content: "Match me!", tenantID: "bamMatch")
    ]
    MessageListView(messages: mockMessages, tenantID: "bamMatch", isDarkMode: true)
}
