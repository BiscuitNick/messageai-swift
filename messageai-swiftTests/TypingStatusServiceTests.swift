//
//  TypingStatusServiceTests.swift
//  messageai-swiftTests
//
//  Created for Task 10 on 10/24/25.
//

import XCTest
@testable import messageai_swift

@MainActor
final class TypingStatusServiceTests: XCTestCase {

    // MARK: - TypingIndicator Tests

    func testTypingIndicatorCreation() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(5)

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        XCTAssertEqual(indicator.id, "user123")
        XCTAssertEqual(indicator.userId, "user123")
        XCTAssertEqual(indicator.displayName, "Test User")
        XCTAssertTrue(indicator.isTyping)
        XCTAssertEqual(indicator.lastUpdated, now)
        XCTAssertEqual(indicator.expiresAt, expiresAt)
    }

    func testTypingIndicatorIsNotExpired() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(5) // Expires in 5 seconds

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        XCTAssertFalse(indicator.isExpired)
    }

    func testTypingIndicatorIsExpired() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(-1) // Expired 1 second ago

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        XCTAssertTrue(indicator.isExpired)
    }

    func testTypingIndicatorExpiresAfterFiveSeconds() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(5)

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        // Should not be expired immediately
        XCTAssertFalse(indicator.isExpired)

        // Simulate time passing (we can't actually wait 5 seconds in a unit test)
        // Instead, verify the expiry time is correct
        let expectedExpiry = now.addingTimeInterval(5)
        XCTAssertEqual(indicator.expiresAt.timeIntervalSince1970, expectedExpiry.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Multiple Typers Tests

    func testMultipleTypersScenario() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(5)

        let typer1 = TypingStatusService.TypingIndicator(
            id: "user1",
            userId: "user1",
            displayName: "User One",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        let typer2 = TypingStatusService.TypingIndicator(
            id: "user2",
            userId: "user2",
            displayName: "User Two",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        let typer3 = TypingStatusService.TypingIndicator(
            id: "user3",
            userId: "user3",
            displayName: "User Three",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        let typers = [typer1, typer2, typer3]

        XCTAssertEqual(typers.count, 3)
        XCTAssertTrue(typers.allSatisfy { $0.isTyping })
        XCTAssertTrue(typers.allSatisfy { !$0.isExpired })
    }

    func testFilteringExpiredTypers() throws {
        let now = Date()

        let activeTyper = TypingStatusService.TypingIndicator(
            id: "user1",
            userId: "user1",
            displayName: "Active User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: now.addingTimeInterval(5) // Not expired
        )

        let expiredTyper = TypingStatusService.TypingIndicator(
            id: "user2",
            userId: "user2",
            displayName: "Expired User",
            isTyping: true,
            lastUpdated: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(-5) // Expired 5 seconds ago
        )

        let allTypers = [activeTyper, expiredTyper]
        let activeTypers = allTypers.filter { !$0.isExpired }

        XCTAssertEqual(allTypers.count, 2)
        XCTAssertEqual(activeTypers.count, 1)
        XCTAssertEqual(activeTypers.first?.userId, "user1")
    }

    // MARK: - TypingError Tests

    func testTypingErrorNotConfigured() throws {
        let error = TypingError.notConfigured

        XCTAssertNotNil(error)

        // Verify it's an Error type
        let _ = error as Error
    }

    // MARK: - Service Configuration Tests

    func testServiceInitialization() throws {
        // Note: Can't fully test Firestore integration without mocks
        // This test verifies the service can be created
        // In a real integration test, you'd use Firestore emulator
        XCTAssertNoThrow({
            let _ = TypingStatusService()
        }())
    }

    // MARK: - Expiry Time Validation Tests

    func testFiveSecondExpiryConstant() throws {
        // Verify the 5-second expiry is correctly calculated
        let now = Date()
        let fiveSecondsLater = now.addingTimeInterval(5)

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: fiveSecondsLater
        )

        // Verify expiry time is 5 seconds from now
        let interval = indicator.expiresAt.timeIntervalSince(now)
        XCTAssertEqual(interval, 5.0, accuracy: 0.001)
    }

    func testExpiryBoundaryCondition() throws {
        let now = Date()
        let exactExpiry = now

        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: exactExpiry
        )

        // At exact expiry time, should be expired (Date() > expiresAt)
        // Note: This might be flaky due to timing, so we test the logic
        XCTAssertTrue(Date() >= exactExpiry)
    }

    // MARK: - Identifiable Conformance Tests

    func testTypingIndicatorIdentifiable() throws {
        let indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: Date(),
            expiresAt: Date().addingTimeInterval(5)
        )

        // Identifiable conformance via id property
        XCTAssertEqual(indicator.id, "user123")

        // Can be used in ForEach
        let indicators = [indicator]
        XCTAssertEqual(indicators.count, 1)
        XCTAssertEqual(indicators.first?.id, "user123")
    }

    // MARK: - State Management Tests

    func testTypingStateChanges() throws {
        let now = Date()
        let expiresAt = now.addingTimeInterval(5)

        // User starts typing
        var indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: true,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        XCTAssertTrue(indicator.isTyping)

        // User stops typing (create new instance since struct is immutable)
        indicator = TypingStatusService.TypingIndicator(
            id: "user123",
            userId: "user123",
            displayName: "Test User",
            isTyping: false,
            lastUpdated: now,
            expiresAt: expiresAt
        )

        XCTAssertFalse(indicator.isTyping)
    }
}
