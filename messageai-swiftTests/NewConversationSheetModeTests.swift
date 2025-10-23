//
//  NewConversationSheetModeTests.swift
//  messageai-swiftTests
//
//  Created by Codex on 10/23/25.
//

import XCTest
@testable import messageai_swift

final class NewConversationSheetModeTests: XCTestCase {

    func testAllCasesIncludeAIChat() throws {
        XCTAssertEqual(NewConversationSheet.Mode.allCases, [.direct, .group, .aiChat])
    }

    func testTitlesReflectProductCopy() throws {
        XCTAssertEqual(NewConversationSheet.Mode.direct.title, "New Message")
        XCTAssertEqual(NewConversationSheet.Mode.group.title, "New Group")
        XCTAssertEqual(NewConversationSheet.Mode.aiChat.title, "Chat with AI")
    }

    func testIdentifiersMatchRawValues() throws {
        for mode in NewConversationSheet.Mode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }
}
