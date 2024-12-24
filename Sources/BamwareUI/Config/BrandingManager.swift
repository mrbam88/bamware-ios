//
//  BrandingManager.swift
//  BamwareUI
//
//  Created by Bilal Malik on 12/24/24.
//
import Foundation
import SwiftUI

@available(iOS 13.0, *)
public class BrandingManager: ObservableObject {
    @Published public var logoURL: String?
    @Published public var primaryColor: Color = Color.blue

    public init(config: [String: Any]) {
        self.logoURL = config["logo"] as? String
        if let hex = config["primaryColor"] as? String {
            self.primaryColor = Color(hex)
        }
    }
}
