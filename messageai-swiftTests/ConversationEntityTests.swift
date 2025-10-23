//
//  ConversationEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import XCTest
@testable import messageai_swift

final class ConversationEntityTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithAllParameters() throws {
        let id = "conv-123"
        let participantIds = ["user-1", "user-2", "user-3"]
        let isGroup = true
        let groupName = "Test Group"
        let groupPictureURL = "https://example.com/group.jpg"
        let adminIds = ["user-1"]
        let lastMessage = "Hello everyone"
        let lastMessageTimestamp = Date()
        let lastSenderId = "user-1"
        let unreadCount = ["user-2": 5, "user-3": 2]
        let lastInteractionByUser = ["user-1": Date(), "user-2": Date().addingTimeInterval(-60)]
        let createdAt = Date().addingTimeInterval(-86400)
        let updatedAt = Date()

        let conversation = ConversationEntity(
            id: id,
            participantIds: participantIds,
            isGroup: isGroup,
            groupName: groupName,
            groupPictureURL: groupPictureURL,
            adminIds: adminIds,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            lastSenderId: lastSenderId,
            unreadCount: unreadCount,
            lastInteractionByUser: lastInteractionByUser,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(conversation.id, id)
        XCTAssertEqual(conversation.participantIds, participantIds)
        XCTAssertEqual(conversation.isGroup, isGroup)
        XCTAssertEqual(conversation.groupName, groupName)
        XCTAssertEqual(conversation.groupPictureURL, groupPictureURL)
        XCTAssertEqual(conversation.adminIds, adminIds)
        XCTAssertEqual(conversation.lastMessage, lastMessage)
        XCTAssertNotNil(conversation.lastMessageTimestamp)
        XCTAssertEqual(conversation.lastMessageTimestamp!.timeIntervalSince1970, lastMessageTimestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(conversation.lastSenderId, lastSenderId)
        XCTAssertEqual(conversation.unreadCount, unreadCount)
        XCTAssertEqual(conversation.lastInteractionByUser.count, lastInteractionByUser.count)
        XCTAssertEqual(conversation.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(conversation.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testInitializationWithDefaultValues() throws {
        let beforeInit = Date()
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"]
        )
        let afterInit = Date()

        // Check defaults
        XCTAssertFalse(conversation.isGroup)
        XCTAssertNil(conversation.groupName)
        XCTAssertNil(conversation.groupPictureURL)
        XCTAssertEqual(conversation.adminIds, [])
        XCTAssertNil(conversation.lastMessage)
        XCTAssertNil(conversation.lastMessageTimestamp)
        XCTAssertNil(conversation.lastSenderId)
        XCTAssertEqual(conversation.unreadCount, [:])
        XCTAssertEqual(conversation.lastInteractionByUser, [:])

        // Check that dates are approximately now
        XCTAssertGreaterThanOrEqual(conversation.createdAt, beforeInit)
        XCTAssertLessThanOrEqual(conversation.createdAt, afterInit)
        XCTAssertGreaterThanOrEqual(conversation.updatedAt, beforeInit)
        XCTAssertLessThanOrEqual(conversation.updatedAt, afterInit)
    }

    func testDirectConversationDefaults() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            isGroup: false
        )

        XCTAssertFalse(conversation.isGroup)
        XCTAssertNil(conversation.groupName)
        XCTAssertNil(conversation.groupPictureURL)
    }

    // MARK: - ParticipantIds Encoding/Decoding Tests

    func testParticipantIdsEncodingDecoding() throws {
        let participantIds = ["user-1", "user-2", "user-3", "user-4"]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: participantIds
        )

        XCTAssertEqual(conversation.participantIds, participantIds)
    }

    func testParticipantIdsWithEmptyArray() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: []
        )

        XCTAssertEqual(conversation.participantIds, [])
    }

    func testParticipantIdsWithSingleParticipant() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1"]
        )

        XCTAssertEqual(conversation.participantIds, ["user-1"])
    }

    func testParticipantIdsSetter() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"]
        )

        conversation.participantIds = ["user-3", "user-4", "user-5"]

        XCTAssertEqual(conversation.participantIds, ["user-3", "user-4", "user-5"])
    }

    func testParticipantIdsWithSpecialCharacters() throws {
        let participantIds = ["user-🚀", "user-with-emoji-👋", "user@123"]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: participantIds
        )

        XCTAssertEqual(conversation.participantIds, participantIds)
    }

    // MARK: - AdminIds Encoding/Decoding Tests

    func testAdminIdsEncodingDecoding() throws {
        let adminIds = ["user-1", "user-2"]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2", "user-3"],
            isGroup: true,
            adminIds: adminIds
        )

        XCTAssertEqual(conversation.adminIds, adminIds)
    }

    func testAdminIdsWithEmptyArray() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            adminIds: []
        )

        XCTAssertEqual(conversation.adminIds, [])
    }

    func testAdminIdsSetter() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2", "user-3"],
            isGroup: true,
            adminIds: ["user-1"]
        )

        conversation.adminIds = ["user-1", "user-2"]

        XCTAssertEqual(conversation.adminIds, ["user-1", "user-2"])
    }

    // MARK: - UnreadCount Encoding/Decoding Tests

    func testUnreadCountEncodingDecoding() throws {
        let unreadCount = ["user-1": 5, "user-2": 10, "user-3": 0]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2", "user-3"],
            unreadCount: unreadCount
        )

        XCTAssertEqual(conversation.unreadCount, unreadCount)
    }

    func testUnreadCountWithEmptyDictionary() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            unreadCount: [:]
        )

        XCTAssertEqual(conversation.unreadCount, [:])
    }

    func testUnreadCountSetter() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            unreadCount: ["user-1": 5]
        )

        conversation.unreadCount = ["user-1": 10, "user-2": 3]

        XCTAssertEqual(conversation.unreadCount, ["user-1": 10, "user-2": 3])
    }

    func testUnreadCountWithZeroValues() throws {
        let unreadCount = ["user-1": 0, "user-2": 0]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            unreadCount: unreadCount
        )

        XCTAssertEqual(conversation.unreadCount, unreadCount)
    }

    func testUnreadCountWithLargeNumbers() throws {
        let unreadCount = ["user-1": 999999, "user-2": 1]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            unreadCount: unreadCount
        )

        XCTAssertEqual(conversation.unreadCount, unreadCount)
    }

    // MARK: - LastInteractionByUser Encoding/Decoding Tests

    func testLastInteractionByUserEncodingDecoding() throws {
        let now = Date()
        let lastInteractionByUser = [
            "user-1": now,
            "user-2": now.addingTimeInterval(-3600),
            "user-3": now.addingTimeInterval(-7200)
        ]
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2", "user-3"],
            lastInteractionByUser: lastInteractionByUser
        )

        XCTAssertEqual(conversation.lastInteractionByUser.count, lastInteractionByUser.count)
        for (userId, date) in lastInteractionByUser {
            XCTAssertNotNil(conversation.lastInteractionByUser[userId])
            XCTAssertEqual(conversation.lastInteractionByUser[userId]!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    func testLastInteractionByUserWithEmptyDictionary() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            lastInteractionByUser: [:]
        )

        XCTAssertEqual(conversation.lastInteractionByUser, [:])
    }

    func testLastInteractionByUserSetter() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            lastInteractionByUser: ["user-1": Date()]
        )

        let newInteractions = ["user-1": Date(), "user-2": Date().addingTimeInterval(-60)]
        conversation.lastInteractionByUser = newInteractions

        XCTAssertEqual(conversation.lastInteractionByUser.count, 2)
    }

    // MARK: - LastSenderId Tests

    func testLastSenderIdSetAndGet() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            lastSenderId: "user-1"
        )

        XCTAssertEqual(conversation.lastSenderId, "user-1")

        conversation.lastSenderId = "user-2"
        XCTAssertEqual(conversation.lastSenderId, "user-2")

        conversation.lastSenderId = nil
        XCTAssertNil(conversation.lastSenderId)
    }

    // MARK: - Mock Fixtures Tests

    func testMockEmpty() throws {
        let conversation = ConversationEntity.mockEmpty

        XCTAssertEqual(conversation.participantIds, [])
        XCTAssertEqual(conversation.adminIds, [])
        XCTAssertEqual(conversation.unreadCount, [:])
        XCTAssertFalse(conversation.isGroup)
    }

    func testMockDirect() throws {
        let conversation = ConversationEntity.mockDirect

        XCTAssertEqual(conversation.participantIds.count, 2)
        XCTAssertFalse(conversation.isGroup)
        XCTAssertNotNil(conversation.lastMessage)
        XCTAssertNotNil(conversation.lastMessageTimestamp)
    }

    func testMockGroup() throws {
        let conversation = ConversationEntity.mockGroup

        XCTAssertTrue(conversation.isGroup)
        XCTAssertEqual(conversation.groupName, "Team Chat")
        XCTAssertNotNil(conversation.groupPictureURL)
        XCTAssertGreaterThan(conversation.participantIds.count, 2)
        XCTAssertEqual(conversation.adminIds.count, 1)
    }

    // MARK: - Edge Cases

    func testMultipleUpdatesToEncodedProperties() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1"]
        )

        // Update multiple times
        conversation.participantIds = ["user-1", "user-2"]
        conversation.participantIds = ["user-1", "user-2", "user-3"]
        conversation.adminIds = ["user-1"]
        conversation.adminIds = ["user-1", "user-2"]
        conversation.unreadCount = ["user-1": 5]
        conversation.unreadCount = ["user-1": 10, "user-2": 3]
        conversation.lastInteractionByUser = ["user-1": Date()]
        conversation.lastInteractionByUser = ["user-1": Date(), "user-2": Date()]

        // Verify final state
        XCTAssertEqual(conversation.participantIds, ["user-1", "user-2", "user-3"])
        XCTAssertEqual(conversation.adminIds, ["user-1", "user-2"])
        XCTAssertEqual(conversation.unreadCount, ["user-1": 10, "user-2": 3])
        XCTAssertEqual(conversation.lastInteractionByUser.count, 2)
    }

    func testLargeArraysAndDictionaries() throws {
        let largeParticipantIds = (1...100).map { "user-\($0)" }
        let largeUnreadCount = Dictionary(uniqueKeysWithValues: largeParticipantIds.map { ($0, Int.random(in: 0...100)) })

        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: largeParticipantIds,
            unreadCount: largeUnreadCount
        )

        XCTAssertEqual(conversation.participantIds.count, 100)
        XCTAssertEqual(conversation.unreadCount.count, 100)
        XCTAssertEqual(conversation.participantIds, largeParticipantIds)
    }

    func testGroupWithoutGroupName() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2", "user-3"],
            isGroup: true,
            groupName: nil
        )

        XCTAssertTrue(conversation.isGroup)
        XCTAssertNil(conversation.groupName)
    }

    func testConversationWithAllNilOptionals() throws {
        let conversation = ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            groupName: nil,
            groupPictureURL: nil,
            lastMessage: nil,
            lastMessageTimestamp: nil
        )

        XCTAssertNil(conversation.groupName)
        XCTAssertNil(conversation.groupPictureURL)
        XCTAssertNil(conversation.lastMessage)
        XCTAssertNil(conversation.lastMessageTimestamp)
    }
}
