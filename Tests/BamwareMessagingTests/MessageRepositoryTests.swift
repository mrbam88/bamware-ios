//
//  MessageRepositoryTests.swift
//  BamwareIOS
//
//  Created by Bilal Malik on 3/22/25.
//

import XCTest
@testable import BamwareMessaging
@testable import BamwareCore

final class MessageRepositoryTests: XCTestCase {
    func test_fetchMessages_returnsTenantMessages() async throws {
        let sut = MockMessageRepository()
        let messages = try await sut.fetchMessages()
        
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.allSatisfy { $0.tenantID == "bamSocial" })
    }
}

// Inside MessageRepositoryTests.swift
private class MockMessageRepository: MessageRepository {
    func fetchMessages() async throws -> [Message] {
        [
            Message(id: "1", content: "Yo, brah!", tenantID: "bamSocial"),
            Message(id: "2", content: "Bamware’s live!", tenantID: "bamSocial")
        ]
    }
}
