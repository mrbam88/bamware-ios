//
//  MessageRepository.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//

public protocol MessageRepository {
    func fetchMessages() async throws -> [Message]
}
