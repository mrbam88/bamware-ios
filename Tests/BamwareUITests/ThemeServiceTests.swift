//
//  Untitled.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//
import XCTest
@testable import BamwareUI
import SwiftUI

final class ThemeServiceTests: XCTestCase {
    func test_currentTheme_returnsDefaultTheme() {
        let sut = MockThemeService()
        let theme = sut.currentTheme()
        
        XCTAssertEqual(theme.primaryColor, .blue)
        XCTAssertFalse(theme.isDarkMode)
    }
    
    func test_currentTheme_tenantSpecific() {
        let sut = MockThemeService(tenantID: "bamSocial")
        let theme = sut.currentTheme()
        
        XCTAssertEqual(theme.tenantID, "bamSocial")
    }
}

// Inside ThemeServiceTests.swift
private class MockThemeService: ThemeService {
    private let tenantID: String
    
    init(tenantID: String = "default") {
        self.tenantID = tenantID
    }
    
    func currentTheme() -> any Theme {
        DefaultTheme(tenantID: tenantID)
    }
}
