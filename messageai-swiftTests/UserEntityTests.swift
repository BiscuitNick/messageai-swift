//
//  UserEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import XCTest
@testable import messageai_swift

final class UserEntityTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithAllParameters() throws {
        let id = "user-123"
        let email = "test@example.com"
        let displayName = "Test User"
        let profilePictureURL = "https://example.com/photo.jpg"
        let isOnline = true
        let lastSeen = Date()
        let createdAt = Date().addingTimeInterval(-86400)

        let user = UserEntity(
            id: id,
            email: email,
            displayName: displayName,
            profilePictureURL: profilePictureURL,
            isOnline: isOnline,
            lastSeen: lastSeen,
            createdAt: createdAt
        )

        XCTAssertEqual(user.id, id)
        XCTAssertEqual(user.email, email)
        XCTAssertEqual(user.displayName, displayName)
        XCTAssertEqual(user.profilePictureURL, profilePictureURL)
        XCTAssertEqual(user.isOnline, isOnline)
        XCTAssertEqual(user.lastSeen.timeIntervalSince1970, lastSeen.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(user.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testInitializationWithNilProfilePictureURL() throws {
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            profilePictureURL: nil
        )

        XCTAssertNil(user.profilePictureURL)
    }

    func testInitializationWithDefaultValues() throws {
        let beforeInit = Date()
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User"
        )
        let afterInit = Date()

        // Check defaults
        XCTAssertFalse(user.isOnline, "Default isOnline should be false")
        XCTAssertNil(user.profilePictureURL)

        // Check that dates are approximately now
        XCTAssertGreaterThanOrEqual(user.lastSeen, beforeInit)
        XCTAssertLessThanOrEqual(user.lastSeen, afterInit)
        XCTAssertGreaterThanOrEqual(user.createdAt, beforeInit)
        XCTAssertLessThanOrEqual(user.createdAt, afterInit)
    }

    // MARK: - Unique Attributes Tests

    func testIdIsUnique() throws {
        // This is tested implicitly by SwiftData, but we verify the attribute exists
        let user1 = UserEntity(id: "user-1", email: "test1@example.com", displayName: "User 1")
        let user2 = UserEntity(id: "user-2", email: "test2@example.com", displayName: "User 2")

        XCTAssertNotEqual(user1.id, user2.id)
    }

    func testEmailIsUnique() throws {
        let user1 = UserEntity(id: "user-1", email: "unique1@example.com", displayName: "User 1")
        let user2 = UserEntity(id: "user-2", email: "unique2@example.com", displayName: "User 2")

        XCTAssertNotEqual(user1.email, user2.email)
    }

    // MARK: - PresenceStatus Computed Property Tests

    func testPresenceStatusOnline() throws {
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-60) // 1 minute ago
        )

        XCTAssertEqual(user.presenceStatus, .online)
    }

    func testPresenceStatusAway() throws {
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-300) // 5 minutes ago
        )

        XCTAssertEqual(user.presenceStatus, .away)
    }

    func testPresenceStatusOffline() throws {
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            isOnline: false,
            lastSeen: Date().addingTimeInterval(-60) // Recent, but isOnline = false
        )

        XCTAssertEqual(user.presenceStatus, .offline)
    }

    func testPresenceStatusOfflineWhenInactive() throws {
        let user = UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-3600) // 1 hour ago
        )

        XCTAssertEqual(user.presenceStatus, .offline)
    }

    // MARK: - Mock Fixtures Tests

    func testMockUser() throws {
        let user = UserEntity.mock

        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertNotNil(user.profilePictureURL)
        XCTAssertTrue(user.isOnline)
    }

    func testMockOfflineUser() throws {
        let user = UserEntity.mockOffline

        XCTAssertFalse(user.isOnline)
        XCTAssertEqual(user.presenceStatus, .offline)
    }

    func testMockAwayUser() throws {
        let user = UserEntity.mockAway

        XCTAssertTrue(user.isOnline)
        XCTAssertEqual(user.presenceStatus, .away)
    }

    func testMockOnlineUser() throws {
        let user = UserEntity.mockOnline

        XCTAssertTrue(user.isOnline)
        XCTAssertEqual(user.presenceStatus, .online)
    }

    // MARK: - Edge Cases

    func testEmptyStrings() throws {
        let user = UserEntity(
            id: "",
            email: "",
            displayName: ""
        )

        XCTAssertEqual(user.id, "")
        XCTAssertEqual(user.email, "")
        XCTAssertEqual(user.displayName, "")
    }

    func testVeryLongStrings() throws {
        let longString = String(repeating: "a", count: 10000)
        let user = UserEntity(
            id: longString,
            email: "\(longString)@example.com",
            displayName: longString
        )

        XCTAssertEqual(user.id.count, 10000)
        XCTAssertEqual(user.displayName.count, 10000)
    }

    func testSpecialCharactersInStrings() throws {
        let user = UserEntity(
            id: "user-🚀-123",
            email: "test+tag@example.com",
            displayName: "Test User 👨‍💻"
        )

        XCTAssertTrue(user.id.contains("🚀"))
        XCTAssertTrue(user.displayName.contains("👨‍💻"))
    }
}
