//
//  DeliveryStatusTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import XCTest
@testable import messageai_swift

final class DeliveryStatusTests: XCTestCase {

    // MARK: - All Cases Tests

    func testAllCasesExist() throws {
        let allCases = DeliveryStatus.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.sending))
        XCTAssertTrue(allCases.contains(.sent))
        XCTAssertTrue(allCases.contains(.delivered))
        XCTAssertTrue(allCases.contains(.read))
    }

    func testAllCasesOrder() throws {
        let allCases = DeliveryStatus.allCases
        XCTAssertEqual(allCases[0], .sending)
        XCTAssertEqual(allCases[1], .sent)
        XCTAssertEqual(allCases[2], .delivered)
        XCTAssertEqual(allCases[3], .read)
    }

    // MARK: - Raw Value Tests

    func testRawValues() throws {
        XCTAssertEqual(DeliveryStatus.sending.rawValue, "sending")
        XCTAssertEqual(DeliveryStatus.sent.rawValue, "sent")
        XCTAssertEqual(DeliveryStatus.delivered.rawValue, "delivered")
        XCTAssertEqual(DeliveryStatus.read.rawValue, "read")
    }

    func testInitFromRawValue() throws {
        XCTAssertEqual(DeliveryStatus(rawValue: "sending"), .sending)
        XCTAssertEqual(DeliveryStatus(rawValue: "sent"), .sent)
        XCTAssertEqual(DeliveryStatus(rawValue: "delivered"), .delivered)
        XCTAssertEqual(DeliveryStatus(rawValue: "read"), .read)
    }

    func testInitFromInvalidRawValue() throws {
        XCTAssertNil(DeliveryStatus(rawValue: "invalid"))
        XCTAssertNil(DeliveryStatus(rawValue: ""))
        XCTAssertNil(DeliveryStatus(rawValue: "SENDING"))
        XCTAssertNil(DeliveryStatus(rawValue: "Sent"))
    }

    // MARK: - Codable Tests

    func testEncodable() throws {
        for status in DeliveryStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let jsonString = String(data: encoded, encoding: .utf8)
            XCTAssertNotNil(jsonString)
            XCTAssertTrue(jsonString!.contains(status.rawValue))
        }
    }

    func testDecodable() throws {
        for status in DeliveryStatus.allCases {
            let jsonData = "\"\(status.rawValue)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(DeliveryStatus.self, from: jsonData)
            XCTAssertEqual(decoded, status)
        }
    }

    func testCodableRoundtrip() throws {
        for status in DeliveryStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DeliveryStatus.self, from: encoded)
            XCTAssertEqual(status, decoded)
        }
    }

    func testDecodingInvalidValue() throws {
        let invalidJSON = "\"invalid_status\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(DeliveryStatus.self, from: invalidJSON))
    }

    // MARK: - Equatable Tests

    func testEquality() throws {
        XCTAssertEqual(DeliveryStatus.sending, .sending)
        XCTAssertEqual(DeliveryStatus.sent, .sent)
        XCTAssertEqual(DeliveryStatus.delivered, .delivered)
        XCTAssertEqual(DeliveryStatus.read, .read)
    }

    func testInequality() throws {
        XCTAssertNotEqual(DeliveryStatus.sending, .sent)
        XCTAssertNotEqual(DeliveryStatus.sent, .delivered)
        XCTAssertNotEqual(DeliveryStatus.delivered, .read)
        XCTAssertNotEqual(DeliveryStatus.sending, .read)
    }

    // MARK: - Sendable Tests

    func testSendableConformance() throws {
        // This test ensures DeliveryStatus conforms to Sendable
        // If it didn't, this would be a compile-time error
        let status: DeliveryStatus = .sending
        Task {
            let _ = status // Should be safe to capture in async context
        }
    }

    // MARK: - Usage in Arrays and Sets

    func testInArray() throws {
        let statuses: [DeliveryStatus] = [.sending, .sent, .delivered, .read]
        XCTAssertEqual(statuses.count, 4)
        XCTAssertTrue(statuses.contains(.sending))
        XCTAssertTrue(statuses.contains(.read))
    }

    func testInSet() throws {
        let statusSet: Set<DeliveryStatus> = [.sending, .sent, .delivered, .read]
        XCTAssertEqual(statusSet.count, 4)
        XCTAssertTrue(statusSet.contains(.sending))
        XCTAssertTrue(statusSet.contains(.read))
    }

    func testSetUniqueness() throws {
        let statusSet: Set<DeliveryStatus> = [.sending, .sending, .sent, .sent]
        XCTAssertEqual(statusSet.count, 2)
    }

    // MARK: - Switch Statement Exhaustiveness

    func testSwitchExhaustiveness() throws {
        for status in DeliveryStatus.allCases {
            let description: String
            switch status {
            case .sending:
                description = "Sending"
            case .sent:
                description = "Sent"
            case .delivered:
                description = "Delivered"
            case .read:
                description = "Read"
            }
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - Typical Message Lifecycle

    func testTypicalMessageLifecycle() throws {
        var currentStatus: DeliveryStatus = .sending
        XCTAssertEqual(currentStatus, .sending)

        currentStatus = .sent
        XCTAssertEqual(currentStatus, .sent)

        currentStatus = .delivered
        XCTAssertEqual(currentStatus, .delivered)

        currentStatus = .read
        XCTAssertEqual(currentStatus, .read)
    }

    // MARK: - Dictionary Keys

    func testAsDropletDictionaryKey() throws {
        let statusCounts: [DeliveryStatus: Int] = [
            .sending: 5,
            .sent: 10,
            .delivered: 15,
            .read: 20
        ]

        XCTAssertEqual(statusCounts[.sending], 5)
        XCTAssertEqual(statusCounts[.sent], 10)
        XCTAssertEqual(statusCounts[.delivered], 15)
        XCTAssertEqual(statusCounts[.read], 20)
    }
}
