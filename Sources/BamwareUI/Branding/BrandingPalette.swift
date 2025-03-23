//
//  BrandingPalette.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//

import SwiftUI
import BamwareCore

public struct BrandingPalette {
    public static func theme(for tenantID: String, isDarkMode: Bool = false) -> any Theme {
        switch tenantID {
        case "bamSocial":
            return BamSocialTheme(isDarkMode: isDarkMode)
        case "bamMatch":
            return BamMatchTheme(isDarkMode: isDarkMode)
        default:
            return DefaultTheme(tenantID: tenantID, isDarkMode: isDarkMode)
        }
    }
}

private struct BamSocialTheme: Theme {
    let tenantID: String
    let primaryColor: Color
    let secondaryColor: Color
    let backgroundColor: Color
    let font: Font
    let isDarkMode: Bool
    
    init(isDarkMode: Bool) {
        self.tenantID = "bamSocial"
        self.isDarkMode = isDarkMode
        self.primaryColor = isDarkMode ? .cyan : .blue
        self.secondaryColor = isDarkMode ? .gray : .gray
        self.backgroundColor = isDarkMode ? .black : .white
        self.font = .body
    }
}

private struct BamMatchTheme: Theme {
    let tenantID: String
    let primaryColor: Color
    let secondaryColor: Color
    let backgroundColor: Color
    let font: Font
    let isDarkMode: Bool
    
    init(isDarkMode: Bool) {
        self.tenantID = "bamMatch"
        self.isDarkMode = isDarkMode
        self.primaryColor = isDarkMode ? .pink : .red
        self.secondaryColor = isDarkMode ? .gray : .orange
        self.backgroundColor = isDarkMode ? .black : .white
        self.font = .body
    }
}
