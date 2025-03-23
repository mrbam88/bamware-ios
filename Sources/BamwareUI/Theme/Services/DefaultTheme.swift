//
//  DefaultTheme.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//
// DefaultTheme.swift
import SwiftUI
import BamwareCore

public struct DefaultTheme: Theme {
    public let tenantID: String
    public let isDarkMode: Bool
    
    public init(tenantID: String, isDarkMode: Bool = false) {
        self.tenantID = tenantID
        self.isDarkMode = isDarkMode
    }
}
