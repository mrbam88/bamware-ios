//
//  DefaultTheme.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//
import SwiftUI
import BamwareCore

public struct DefaultTheme: Theme {
    public let tenantID: String
    public let isDarkMode: Bool
    public let primaryColor: Color
    public let secondaryColor: Color
    public let backgroundColor: Color
    public let font: Font

    public init(tenantID: String, isDarkMode: Bool = false) {
        self.tenantID = tenantID
        self.isDarkMode = isDarkMode
        self.primaryColor = isDarkMode ? .cyan : .blue
        self.secondaryColor = isDarkMode ? .gray : .secondary
        self.backgroundColor = isDarkMode ? .black : .white
        self.font = .body
    }
}
