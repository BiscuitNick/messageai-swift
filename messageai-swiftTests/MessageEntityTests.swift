//
//  MessageEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import XCTest
@testable import messageai_swift

final class MessageEntityTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithAllParameters() throws {
        let id = "msg-123"
        let conversationId = "conv-456"
        let senderId = "user-1"
        let text = "Hello, world!"
        let timestamp = Date()
        let deliveryStatus = DeliveryStatus.delivered
        let readBy = ["user-2", "user-3"]
        let readReceipts = Dictionary(uniqueKeysWithValues: readBy.map { ($0, timestamp) })
        let updatedAt = Date()

        let message = MessageEntity(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            text: text,
            timestamp: timestamp,
            deliveryStatus: deliveryStatus,
            readReceipts: readReceipts,
            updatedAt: updatedAt
        )

        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.conversationId, conversationId)
        XCTAssertEqual(message.senderId, senderId)
        XCTAssertEqual(message.text, text)
        XCTAssertEqual(message.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(message.deliveryStatus, deliveryStatus)
        XCTAssertEqual(Set(message.readBy), Set(readBy))
        XCTAssertEqual(message.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testInitializationWithDefaultValues() throws {
        let beforeInit = Date()
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test message"
        )
        let afterInit = Date()

        // Check defaults
        XCTAssertEqual(message.deliveryStatus, .sending)
        XCTAssertEqual(message.readBy, [])

        // Check that dates are approximately now
        XCTAssertGreaterThanOrEqual(message.timestamp, beforeInit)
        XCTAssertLessThanOrEqual(message.timestamp, afterInit)
        XCTAssertGreaterThanOrEqual(message.updatedAt, beforeInit)
        XCTAssertLessThanOrEqual(message.updatedAt, afterInit)
    }

    // MARK: - DeliveryStatus Encoding/Decoding Tests

    func testDeliveryStatusEncodingDecoding() throws {
        for status in DeliveryStatus.allCases {
            let message = MessageEntity(
                id: "msg-1",
                conversationId: "conv-1",
                senderId: "user-1",
                text: "Test",
                deliveryStatus: status
            )

            XCTAssertEqual(message.deliveryStatus, status)
            XCTAssertEqual(message.deliveryStatusRawValue, status.rawValue)
        }
    }

    func testDeliveryStatusSending() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Sending...",
            deliveryStatus: .sending
        )

        XCTAssertEqual(message.deliveryStatus, .sending)
    }

    func testDeliveryStatusSent() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Sent message",
            deliveryStatus: .sent
        )

        XCTAssertEqual(message.deliveryStatus, .sent)
    }

    func testDeliveryStatusDelivered() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Delivered message",
            deliveryStatus: .delivered
        )

        XCTAssertEqual(message.deliveryStatus, .delivered)
    }

    func testDeliveryStatusRead() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Read message",
            deliveryStatus: .read
        )

        XCTAssertEqual(message.deliveryStatus, .read)
    }

    func testDeliveryStatusSetter() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test",
            deliveryStatus: .sending
        )

        message.deliveryStatus = .sent
        XCTAssertEqual(message.deliveryStatus, .sent)

        message.deliveryStatus = .delivered
        XCTAssertEqual(message.deliveryStatus, .delivered)

        message.deliveryStatus = .read
        XCTAssertEqual(message.deliveryStatus, .read)
    }

    func testDeliveryStatusProgression() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test"
        )

        // Simulate typical message lifecycle
        XCTAssertEqual(message.deliveryStatus, .sending)

        message.deliveryStatus = .sent
        XCTAssertEqual(message.deliveryStatus, .sent)

        message.deliveryStatus = .delivered
        XCTAssertEqual(message.deliveryStatus, .delivered)

        message.deliveryStatus = .read
        XCTAssertEqual(message.deliveryStatus, .read)
    }

    // MARK: - ReadBy Encoding/Decoding Tests

    func testReadByEncodingDecoding() throws {
        let readBy = ["user-1", "user-2", "user-3"]
        let timestamp = Date()
        let readReceipts = Dictionary(uniqueKeysWithValues: readBy.map { ($0, timestamp) })
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-sender",
            text: "Test",
            readReceipts: readReceipts
        )

        XCTAssertEqual(Set(message.readBy), Set(readBy))
    }

    func testReadByWithEmptyArray() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test",
            readReceipts: [:]
        )

        XCTAssertEqual(message.readBy, [])
    }

    func testReadBySetter() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test",
            readReceipts: [:]
        )

        message.readBy = ["user-2"]
        XCTAssertEqual(message.readBy, ["user-2"])

        message.readBy = ["user-2", "user-3"]
        XCTAssertEqual(message.readBy, ["user-2", "user-3"])
    }

    func testReadByAccumulation() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test",
            readReceipts: [:]
        )

        // Simulate users reading the message over time
        message.readBy = ["user-2"]
        XCTAssertEqual(message.readBy.count, 1)

        message.readBy.append("user-3")
        XCTAssertEqual(message.readBy.count, 2)

        message.readBy.append("user-4")
        XCTAssertEqual(message.readBy.count, 3)
    }

    // MARK: - Mock Fixtures Tests

    func testMockSending() throws {
        let message = MessageEntity.mockSending

        XCTAssertEqual(message.deliveryStatus, .sending)
        XCTAssertEqual(message.readBy, [])
    }

    func testMockSent() throws {
        let message = MessageEntity.mockSent

        XCTAssertEqual(message.deliveryStatus, .sent)
    }

    func testMockDelivered() throws {
        let message = MessageEntity.mockDelivered

        XCTAssertEqual(message.deliveryStatus, .delivered)
    }

    func testMockRead() throws {
        let message = MessageEntity.mockRead

        XCTAssertEqual(message.deliveryStatus, .read)
        XCTAssertFalse(message.readBy.isEmpty)
    }

    func testMockMultipleReaders() throws {
        let message = MessageEntity.mockMultipleReaders

        XCTAssertEqual(message.deliveryStatus, .read)
        XCTAssertGreaterThan(message.readBy.count, 1)
    }

    // MARK: - Edge Cases

    func testEmptyText() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: ""
        )

        XCTAssertEqual(message.text, "")
    }

    func testVeryLongText() throws {
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 1000)
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: longText
        )

        XCTAssertEqual(message.text, longText)
    }

    func testTextWithSpecialCharacters() throws {
        let specialText = "Hello 👋 World 🌍\nNew line\tTab\n\n\nMultiple lines\n"
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: specialText
        )

        XCTAssertEqual(message.text, specialText)
    }

    func testTextWithEmojis() throws {
        let emojiText = "🚀🎉💻🔥👍😊"
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: emojiText
        )

        XCTAssertEqual(message.text, emojiText)
    }

    func testMultipleUpdatesToEncodedProperties() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test"
        )

        // Update multiple times
        message.deliveryStatus = .sending
        message.deliveryStatus = .sent
        message.readBy = ["user-2"]
        message.readBy = ["user-2", "user-3"]
        message.deliveryStatus = .delivered
        message.deliveryStatus = .read

        // Verify final state
        XCTAssertEqual(message.deliveryStatus, .read)
        XCTAssertEqual(message.readBy, ["user-2", "user-3"])
    }

    func testLargeReadByArray() throws {
        let largeReadBy = (1...100).map { "user-\($0)" }
        let timestamp = Date()
        let largeReadReceipts = Dictionary(uniqueKeysWithValues: largeReadBy.map { ($0, timestamp) })
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-sender",
            text: "Broadcast message",
            readReceipts: largeReadReceipts
        )

        XCTAssertEqual(message.readBy.count, 100)
        XCTAssertEqual(Set(message.readBy), Set(largeReadBy))
    }

    func testInvalidDeliveryStatusRawValue() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test"
        )

        // Manually set invalid raw value
        message.deliveryStatusRawValue = "invalid-status"

        // Should fallback to .sending
        XCTAssertEqual(message.deliveryStatus, .sending)
    }

    // MARK: - Scheduling Intent Metadata Tests

    func testInitializationWithSchedulingMetadata() throws {
        let id = "msg-scheduling-1"
        let conversationId = "conv-123"
        let senderId = "user-1"
        let text = "Let's meet tomorrow at 2pm"
        let timestamp = Date()
        let schedulingIntent = "high"
        let intentConfidence = 0.85
        let intentAnalyzedAt = Date()
        let schedulingKeywords = ["meet", "tomorrow", "2pm"]

        let message = MessageEntity(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            text: text,
            timestamp: timestamp,
            schedulingIntent: schedulingIntent,
            intentConfidence: intentConfidence,
            intentAnalyzedAt: intentAnalyzedAt,
            schedulingKeywords: schedulingKeywords
        )

        XCTAssertEqual(message.schedulingIntent, schedulingIntent)
        XCTAssertEqual(message.intentConfidence, intentConfidence)
        XCTAssertNotNil(message.intentAnalyzedAt)
        XCTAssertEqual(message.schedulingKeywords, schedulingKeywords)
        XCTAssertTrue(message.hasSchedulingData)
    }

    func testInitializationWithoutSchedulingMetadata() throws {
        let message = MessageEntity(
            id: "msg-no-scheduling",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Just a regular message"
        )

        // Verify backward compatibility - should handle missing scheduling data
        XCTAssertNil(message.schedulingIntent)
        XCTAssertNil(message.intentConfidence)
        XCTAssertNil(message.intentAnalyzedAt)
        XCTAssertEqual(message.schedulingKeywords, [])
        XCTAssertFalse(message.hasSchedulingData)
    }

    func testSchedulingKeywordsEncodingDecoding() throws {
        let keywords = ["meeting", "schedule", "calendar", "appointment"]
        let message = MessageEntity(
            id: "msg-keywords",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Schedule a meeting",
            schedulingKeywords: keywords
        )

        XCTAssertEqual(message.schedulingKeywords, keywords)
    }

    func testSchedulingKeywordsWithEmptyArray() throws {
        let message = MessageEntity(
            id: "msg-empty-keywords",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Test",
            schedulingKeywords: []
        )

        XCTAssertEqual(message.schedulingKeywords, [])
    }

    func testSchedulingKeywordsSetter() throws {
        let message = MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Test"
        )

        // Initially empty
        XCTAssertEqual(message.schedulingKeywords, [])

        // Set keywords
        message.schedulingKeywords = ["meet", "tomorrow"]
        XCTAssertEqual(message.schedulingKeywords, ["meet", "tomorrow"])

        // Update keywords
        message.schedulingKeywords = ["meet", "tomorrow", "noon"]
        XCTAssertEqual(message.schedulingKeywords, ["meet", "tomorrow", "noon"])
    }

    func testSchedulingIntentLowConfidence() throws {
        let message = MessageEntity(
            id: "msg-low-conf",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Maybe we could meet?",
            schedulingIntent: "low",
            intentConfidence: 0.3,
            intentAnalyzedAt: Date()
        )

        XCTAssertEqual(message.schedulingIntent, "low")
        XCTAssertEqual(message.intentConfidence, 0.3)
        XCTAssertTrue(message.hasSchedulingData)
    }

    func testSchedulingIntentHighConfidence() throws {
        let message = MessageEntity(
            id: "msg-high-conf",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Let's schedule a meeting for Friday at 3pm",
            schedulingIntent: "high",
            intentConfidence: 0.95,
            intentAnalyzedAt: Date(),
            schedulingKeywords: ["schedule", "meeting", "Friday", "3pm"]
        )

        XCTAssertEqual(message.schedulingIntent, "high")
        XCTAssertEqual(message.intentConfidence, 0.95)
        XCTAssertTrue(message.hasSchedulingData)
        XCTAssertEqual(message.schedulingKeywords.count, 4)
    }

    func testSchedulingIntentMediumConfidence() throws {
        let message = MessageEntity(
            id: "msg-med-conf",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Should we meet next week?",
            schedulingIntent: "medium",
            intentConfidence: 0.6,
            intentAnalyzedAt: Date(),
            schedulingKeywords: ["meet", "next week"]
        )

        XCTAssertEqual(message.schedulingIntent, "medium")
        XCTAssertEqual(message.intentConfidence, 0.6)
        XCTAssertTrue(message.hasSchedulingData)
    }

    func testSchedulingIntentNoneClassification() throws {
        let message = MessageEntity(
            id: "msg-none",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "The weather is nice today",
            schedulingIntent: "none",
            intentConfidence: 0.1,
            intentAnalyzedAt: Date(),
            schedulingKeywords: []
        )

        XCTAssertEqual(message.schedulingIntent, "none")
        XCTAssertEqual(message.intentConfidence, 0.1)
        XCTAssertTrue(message.hasSchedulingData)
        XCTAssertEqual(message.schedulingKeywords, [])
    }

    func testHasSchedulingDataFalseWhenNoAnalysis() throws {
        let message = MessageEntity(
            id: "msg-no-analysis",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Test message"
        )

        XCTAssertFalse(message.hasSchedulingData)
        XCTAssertNil(message.intentAnalyzedAt)
    }

    func testHasSchedulingDataTrueWhenAnalyzed() throws {
        let message = MessageEntity(
            id: "msg-analyzed",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Test message",
            schedulingIntent: "none",
            intentConfidence: 0.1,
            intentAnalyzedAt: Date()
        )

        XCTAssertTrue(message.hasSchedulingData)
        XCTAssertNotNil(message.intentAnalyzedAt)
    }

    func testSchedulingMetadataWithPriorityMetadata() throws {
        // Test that both priority and scheduling metadata can coexist
        let message = MessageEntity(
            id: "msg-both",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Urgent: Schedule meeting ASAP",
            priorityScore: 9,
            priorityLabel: "urgent",
            priorityRationale: "Contains urgent keyword",
            priorityAnalyzedAt: Date(),
            schedulingIntent: "high",
            intentConfidence: 0.92,
            intentAnalyzedAt: Date(),
            schedulingKeywords: ["schedule", "meeting", "ASAP"]
        )

        // Verify priority metadata
        XCTAssertTrue(message.hasPriorityData)
        XCTAssertEqual(message.priorityScore, 9)
        XCTAssertEqual(message.priorityLabel, "urgent")

        // Verify scheduling metadata
        XCTAssertTrue(message.hasSchedulingData)
        XCTAssertEqual(message.schedulingIntent, "high")
        XCTAssertEqual(message.intentConfidence, 0.92)
        XCTAssertEqual(message.schedulingKeywords, ["schedule", "meeting", "ASAP"])
    }

    func testLargeSchedulingKeywordsArray() throws {
        let largeKeywords = (1...50).map { "keyword-\($0)" }
        let message = MessageEntity(
            id: "msg-large-keywords",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Test",
            schedulingKeywords: largeKeywords
        )

        XCTAssertEqual(message.schedulingKeywords.count, 50)
        XCTAssertEqual(Set(message.schedulingKeywords), Set(largeKeywords))
    }

    func testSchedulingKeywordsWithSpecialCharacters() throws {
        let specialKeywords = ["meet@office", "2:30pm", "next-week", "conference_room"]
        let message = MessageEntity(
            id: "msg-special",
            conversationId: "conv-123",
            senderId: "user-1",
            text: "Test",
            schedulingKeywords: specialKeywords
        )

        XCTAssertEqual(message.schedulingKeywords, specialKeywords)
    }
}
