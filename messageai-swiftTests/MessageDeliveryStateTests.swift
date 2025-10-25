//
//  MessageDeliveryStateTests.swift
//  messageai-swiftTests
//
//  Updated for MessageDeliveryState schema on 10/24/25.
//

import XCTest
@testable import messageai_swift

final class MessageDeliveryStateTests: XCTestCase {

    // MARK: - All Cases Tests

    func testAllCasesExist() throws {
        let allCases = MessageDeliveryState.allCases
        XCTAssertEqual(allCases.count, 5) // pending, sent, delivered, read, failed
        XCTAssertTrue(allCases.contains(.pending))
        XCTAssertTrue(allCases.contains(.sent))
        XCTAssertTrue(allCases.contains(.delivered))
        XCTAssertTrue(allCases.contains(.read))
        XCTAssertTrue(allCases.contains(.failed))
    }

    func testAllCasesOrder() throws {
        let allCases = MessageDeliveryState.allCases
        XCTAssertEqual(allCases[0], .pending)
        XCTAssertEqual(allCases[1], .sent)
        XCTAssertEqual(allCases[2], .delivered)
        XCTAssertEqual(allCases[3], .read)
        XCTAssertEqual(allCases[4], .failed)
    }

    // MARK: - Raw Value Tests

    func testRawValues() throws {
        XCTAssertEqual(MessageDeliveryState.pending.rawValue, "pending")
        XCTAssertEqual(MessageDeliveryState.sent.rawValue, "sent")
        XCTAssertEqual(MessageDeliveryState.delivered.rawValue, "delivered")
        XCTAssertEqual(MessageDeliveryState.read.rawValue, "read")
        XCTAssertEqual(MessageDeliveryState.failed.rawValue, "failed")
    }

    // MARK: - Migration Tests

    func testMigrationFromLegacySending() throws {
        let state = MessageDeliveryState(fromLegacy: "sending")
        XCTAssertEqual(state, .pending)
    }

    func testMigrationFromLegacySent() throws {
        let state = MessageDeliveryState(fromLegacy: "sent")
        XCTAssertEqual(state, .sent)
    }

    func testMigrationFromLegacyDelivered() throws {
        let state = MessageDeliveryState(fromLegacy: "delivered")
        XCTAssertEqual(state, .delivered)
    }

    func testMigrationFromLegacyRead() throws {
        let state = MessageDeliveryState(fromLegacy: "read")
        XCTAssertEqual(state, .read)
    }

    func testMigrationFromInvalidValue() throws {
        let state = MessageDeliveryState(fromLegacy: "invalid")
        XCTAssertEqual(state, .sent) // default fallback
    }

    func testMigrationFromPending() throws {
        let state = MessageDeliveryState(fromLegacy: "pending")
        XCTAssertEqual(state, .pending)
    }

    func testMigrationFromFailed() throws {
        let state = MessageDeliveryState(fromLegacy: "failed")
        XCTAssertEqual(state, .failed)
    }

    // MARK: - Codable Tests

    func testEncodable() throws {
        for state in MessageDeliveryState.allCases {
            let encoded = try JSONEncoder().encode(state)
            let jsonString = String(data: encoded, encoding: .utf8)
            XCTAssertNotNil(jsonString)
            XCTAssertTrue(jsonString!.contains(state.rawValue))
        }
    }

    func testDecodable() throws {
        for state in MessageDeliveryState.allCases {
            let jsonData = "\"\(state.rawValue)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(MessageDeliveryState.self, from: jsonData)
            XCTAssertEqual(decoded, state)
        }
    }

    func testCodableRoundtrip() throws {
        for state in MessageDeliveryState.allCases {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(MessageDeliveryState.self, from: encoded)
            XCTAssertEqual(state, decoded)
        }
    }

    // MARK: - Equatable Tests

    func testEquality() throws {
        XCTAssertEqual(MessageDeliveryState.pending, .pending)
        XCTAssertEqual(MessageDeliveryState.sent, .sent)
        XCTAssertEqual(MessageDeliveryState.delivered, .delivered)
        XCTAssertEqual(MessageDeliveryState.read, .read)
        XCTAssertEqual(MessageDeliveryState.failed, .failed)
    }

    func testInequality() throws {
        XCTAssertNotEqual(MessageDeliveryState.pending, .sent)
        XCTAssertNotEqual(MessageDeliveryState.sent, .delivered)
        XCTAssertNotEqual(MessageDeliveryState.delivered, .read)
        XCTAssertNotEqual(MessageDeliveryState.read, .failed)
        XCTAssertNotEqual(MessageDeliveryState.pending, .failed)
    }

    // MARK: - Sendable Tests

    func testSendableConformance() throws {
        let state: MessageDeliveryState = .pending
        Task {
            let _ = state // Should be safe to capture in async context
        }
    }

    // MARK: - Typical Message Lifecycle

    func testTypicalMessageLifecycle() throws {
        var currentState: MessageDeliveryState = .pending
        XCTAssertEqual(currentState, .pending)

        currentState = .sent
        XCTAssertEqual(currentState, .sent)

        currentState = .delivered
        XCTAssertEqual(currentState, .delivered)

        currentState = .read
        XCTAssertEqual(currentState, .read)
    }

    func testFailedMessageLifecycle() throws {
        var currentState: MessageDeliveryState = .pending
        XCTAssertEqual(currentState, .pending)

        // Message failed to send
        currentState = .failed
        XCTAssertEqual(currentState, .failed)
    }

    // MARK: - Dictionary Keys

    func testAsDictionaryKey() throws {
        let stateCounts: [MessageDeliveryState: Int] = [
            .pending: 5,
            .sent: 10,
            .delivered: 15,
            .read: 20,
            .failed: 2
        ]

        XCTAssertEqual(stateCounts[.pending], 5)
        XCTAssertEqual(stateCounts[.sent], 10)
        XCTAssertEqual(stateCounts[.delivered], 15)
        XCTAssertEqual(stateCounts[.read], 20)
        XCTAssertEqual(stateCounts[.failed], 2)
    }
}
