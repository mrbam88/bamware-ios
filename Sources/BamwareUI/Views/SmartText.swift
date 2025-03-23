//
//  SmartText.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/23/25.
//

import SwiftUI
import BamwareCore

public struct SmartText: View {
    private let text: String
    private let theme: any Theme
    
    public init(_ text: String, theme: any Theme = DefaultTheme(tenantID: "bamSocial")) {
        self.text = text
        self.theme = theme
    }
    
    public var body: some View {
        Text(text)
            .foregroundColor(theme.primaryColor)
            .font(theme.font)
    }
}
