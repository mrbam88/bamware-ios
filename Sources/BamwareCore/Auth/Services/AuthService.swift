//
//  AuthService.swift
//  BamwareUI
//
//  Created by Bilal Malik on 3/22/25.
//


// AuthService.swift
public protocol AuthService {
    var currentUser: User? { get }
    func validateToken(_ token: String) async throws
}
