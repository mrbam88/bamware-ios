//
//  Tenant.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//

public struct Tenant: Entity {
    public let id: String
    public let tenantID: String  // Entity conformance
    
    public init(id: String, tenantID: String) {
        self.id = id
        self.tenantID = tenantID
    }
}
