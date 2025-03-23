//
//  Message.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//
import BamwareCore

public struct Message: Entity {
    public let id: String
    public let content: String
    public let tenantID: String
    
    public init(id: String, content: String, tenantID: String) {
        self.id = id
        self.content = content
        self.tenantID = tenantID
    }
}
