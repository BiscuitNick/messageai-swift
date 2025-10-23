//
//  PresenceStatusTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import XCTest
import SwiftUI
@testable import messageai_swift

final class PresenceStatusTests: XCTestCase {

    // MARK: - Status Calculation Tests

    func testStatusCalculation_OnlineWhenRecentlyActive() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-60) // 1 minute ago

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .online)
    }

    func testStatusCalculation_OnlineAtExactBoundary() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-120) // Exactly 120 seconds

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .online, "120 seconds should still be online (≤ 120)")
    }

    func testStatusCalculation_AwayWhenModeratelyInactive() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-300) // 5 minutes ago

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .away)
    }

    func testStatusCalculation_AwayAtLowerBoundary() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-121) // Just over 120 seconds

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .away)
    }

    func testStatusCalculation_AwayAtUpperBoundary() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-600) // Exactly 600 seconds

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .away, "600 seconds should still be away (≤ 600)")
    }

    func testStatusCalculation_OfflineWhenVeryInactive() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-3600) // 1 hour ago

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .offline)
    }

    func testStatusCalculation_OfflineJustPastBoundary() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-601) // Just over 600 seconds

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .offline)
    }

    func testStatusCalculation_OfflineWhenNotOnline() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(-30) // Very recent, but isOnline = false

        let status = PresenceStatus.status(isOnline: false, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .offline, "Should be offline when isOnline is false regardless of lastSeen")
    }

    func testStatusCalculation_NegativeInterval() throws {
        let now = Date()
        let lastSeen = now.addingTimeInterval(100) // Future date

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .online, "Negative intervals should be clamped to 0 via max()")
    }

    func testStatusCalculation_ExactlyZeroInterval() throws {
        let now = Date()
        let lastSeen = now // Same time

        let status = PresenceStatus.status(isOnline: true, lastSeen: lastSeen, reference: now)

        XCTAssertEqual(status, .online)
    }

    // MARK: - UI Properties Tests

    func testSortRank() throws {
        XCTAssertEqual(PresenceStatus.online.sortRank, 0)
        XCTAssertEqual(PresenceStatus.away.sortRank, 1)
        XCTAssertEqual(PresenceStatus.offline.sortRank, 2)
    }

    func testSortRankOrdering() throws {
        XCTAssertLessThan(PresenceStatus.online.sortRank, PresenceStatus.away.sortRank)
        XCTAssertLessThan(PresenceStatus.away.sortRank, PresenceStatus.offline.sortRank)
    }

    func testIndicatorColor() throws {
        XCTAssertEqual(PresenceStatus.online.indicatorColor, .green)
        XCTAssertEqual(PresenceStatus.away.indicatorColor, .orange)
        XCTAssertEqual(PresenceStatus.offline.indicatorColor, .gray)
    }

    func testDisplayLabel() throws {
        XCTAssertEqual(PresenceStatus.online.displayLabel, "Online")
        XCTAssertEqual(PresenceStatus.away.displayLabel, "Away")
        XCTAssertEqual(PresenceStatus.offline.displayLabel, "Offline")
    }

    // MARK: - All Cases Test

    func testAllCasesExists() throws {
        let allCases = PresenceStatus.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.online))
        XCTAssertTrue(allCases.contains(.away))
        XCTAssertTrue(allCases.contains(.offline))
    }

    // MARK: - Codable Tests

    func testCodableRoundtrip() throws {
        for status in PresenceStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(PresenceStatus.self, from: encoded)
            XCTAssertEqual(status, decoded)
        }
    }

    func testRawValues() throws {
        XCTAssertEqual(PresenceStatus.online.rawValue, "online")
        XCTAssertEqual(PresenceStatus.away.rawValue, "away")
        XCTAssertEqual(PresenceStatus.offline.rawValue, "offline")
    }

    func testInitFromRawValue() throws {
        XCTAssertEqual(PresenceStatus(rawValue: "online"), .online)
        XCTAssertEqual(PresenceStatus(rawValue: "away"), .away)
        XCTAssertEqual(PresenceStatus(rawValue: "offline"), .offline)
        XCTAssertNil(PresenceStatus(rawValue: "invalid"))
    }
}
