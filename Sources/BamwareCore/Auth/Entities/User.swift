//
//  User.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//

// User.swift
public struct User: Entity {
    public let id: String
    public let tenantID: String
    public let roles: [String]
    
    public init(id: String, tenantID: String, roles: [String]) {
        self.id = id
        self.tenantID = tenantID
        self.roles = roles
    }
}
