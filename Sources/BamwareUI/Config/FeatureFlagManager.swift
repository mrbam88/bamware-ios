//
//  FeatureFlagManager.swift
//  BamwareUI
//
//  Created by Bilal Malik on 12/24/24.
//
import Foundation
import SwiftUI

@available(iOS 13.0, *)
public class FeatureFlagManager: ObservableObject {
    @Published public var enabledFeatures: [String] = []

    public init(config: [String: Any]) {
        if let features = config["features"] as? [String] {
            self.enabledFeatures = features
        }
    }

    public func isFeatureEnabled(_ feature: String) -> Bool {
        return enabledFeatures.contains(feature)
    }
}
