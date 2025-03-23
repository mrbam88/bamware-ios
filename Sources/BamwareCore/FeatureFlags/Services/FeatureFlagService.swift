//
//  Untitled.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//

public protocol FeatureFlagService {
    func isEnabled(_ feature: String, tenantID: String) -> Bool
}
