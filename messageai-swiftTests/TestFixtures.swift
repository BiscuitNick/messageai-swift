//
//  TestFixtures.swift
//  messageai-swiftTests
//
//  Created by Claude Code
//

import Foundation
@testable import messageai_swift

// MARK: - UserEntity Mock Extensions

extension UserEntity {
    static var mock: UserEntity {
        UserEntity(
            id: "user-1",
            email: "test@example.com",
            displayName: "Test User",
            profilePictureURL: "https://example.com/photo.jpg",
            isOnline: true,
            lastSeen: Date(),
            createdAt: Date()
        )
    }

    static var mockOffline: UserEntity {
        UserEntity(
            id: "user-2",
            email: "offline@example.com",
            displayName: "Offline User",
            profilePictureURL: nil,
            isOnline: false,
            lastSeen: Date().addingTimeInterval(-3600), // 1 hour ago
            createdAt: Date().addingTimeInterval(-86400) // 1 day ago
        )
    }

    static var mockAway: UserEntity {
        UserEntity(
            id: "user-3",
            email: "away@example.com",
            displayName: "Away User",
            profilePictureURL: nil,
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-300), // 5 minutes ago
            createdAt: Date().addingTimeInterval(-86400)
        )
    }

    static var mockOnline: UserEntity {
        UserEntity(
            id: "user-4",
            email: "online@example.com",
            displayName: "Online User",
            profilePictureURL: nil,
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-30), // 30 seconds ago
            createdAt: Date()
        )
    }
}

// MARK: - ConversationEntity Mock Extensions

extension ConversationEntity {
    static var mockEmpty: ConversationEntity {
        ConversationEntity(
            id: "conv-empty",
            participantIds: [],
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [],
            lastMessage: nil,
            lastMessageTimestamp: nil,
            unreadCount: [:],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var mockDirect: ConversationEntity {
        ConversationEntity(
            id: "conv-1",
            participantIds: ["user-1", "user-2"],
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [],
            lastMessage: "Hey, how are you?",
            lastMessageTimestamp: Date(),
            unreadCount: ["user-2": 3],
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date()
        )
    }

    static var mockGroup: ConversationEntity {
        ConversationEntity(
            id: "conv-2",
            participantIds: ["user-1", "user-2", "user-3", "user-4"],
            isGroup: true,
            groupName: "Team Chat",
            groupPictureURL: "https://example.com/group.jpg",
            adminIds: ["user-1"],
            lastMessage: "Meeting at 3pm",
            lastMessageTimestamp: Date(),
            unreadCount: ["user-2": 5, "user-3": 2],
            createdAt: Date().addingTimeInterval(-172800),
            updatedAt: Date()
        )
    }

    static var mockMultipleUnread: ConversationEntity {
        ConversationEntity(
            id: "conv-3",
            participantIds: ["user-1", "user-2"],
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [],
            lastMessage: "Last message",
            lastMessageTimestamp: Date(),
            unreadCount: ["user-1": 10, "user-2": 0],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - MessageEntity Mock Extensions

extension MessageEntity {
    static var mockSending: MessageEntity {
        MessageEntity(
            id: "msg-1",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "Hello, sending...",
            timestamp: Date(),
            deliveryStatus: .sending,
            readBy: [],
            updatedAt: Date()
        )
    }

    static var mockSent: MessageEntity {
        MessageEntity(
            id: "msg-2",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "This message was sent",
            timestamp: Date(),
            deliveryStatus: .sent,
            readBy: [],
            updatedAt: Date()
        )
    }

    static var mockDelivered: MessageEntity {
        MessageEntity(
            id: "msg-3",
            conversationId: "conv-1",
            senderId: "user-2",
            text: "This message was delivered",
            timestamp: Date().addingTimeInterval(-60),
            deliveryStatus: .delivered,
            readBy: [],
            updatedAt: Date()
        )
    }

    static var mockRead: MessageEntity {
        MessageEntity(
            id: "msg-4",
            conversationId: "conv-1",
            senderId: "user-1",
            text: "This message was read",
            timestamp: Date().addingTimeInterval(-120),
            deliveryStatus: .read,
            readBy: ["user-2"],
            updatedAt: Date()
        )
    }

    static var mockMultipleReaders: MessageEntity {
        MessageEntity(
            id: "msg-5",
            conversationId: "conv-2",
            senderId: "user-1",
            text: "Group message read by multiple users",
            timestamp: Date().addingTimeInterval(-300),
            deliveryStatus: .read,
            readBy: ["user-2", "user-3", "user-4"],
            updatedAt: Date()
        )
    }
}
