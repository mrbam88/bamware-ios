//
//  UserPermissionsService.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/23/25.
//

public protocol UserPermissionsService {
    func hasPermission(_ permission: String, tenantID: String) -> Bool
}
