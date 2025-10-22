//
//  Models.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import SwiftData

@Model
final class UserEntity {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var email: String
    var displayName: String
    var profilePictureURL: String?
    var isOnline: Bool
    var lastSeen: Date
    var createdAt: Date

    init(
        id: String,
        email: String,
        displayName: String,
        profilePictureURL: String? = nil,
        isOnline: Bool = false,
        lastSeen: Date = .init(),
        createdAt: Date = .init()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.createdAt = createdAt
    }
}

@Model
final class ConversationEntity {
    @Attribute(.unique) var id: String
    var participantIdsData: Data
    var isGroup: Bool
    var groupName: String?
    var groupPictureURL: String?
    var adminIdsData: Data
    var lastMessage: String?
    var lastMessageTimestamp: Date?
    var unreadCountData: Data
    var createdAt: Date

    init(
        id: String,
        participantIds: [String],
        isGroup: Bool = false,
        groupName: String? = nil,
        groupPictureURL: String? = nil,
        adminIds: [String] = [],
        lastMessage: String? = nil,
        lastMessageTimestamp: Date? = nil,
        unreadCount: [String: Int] = [:],
        createdAt: Date = .init()
    ) {
        self.id = id
        self.participantIdsData = LocalJSONCoder.encode(participantIds)
        self.isGroup = isGroup
        self.groupName = groupName
        self.groupPictureURL = groupPictureURL
        self.adminIdsData = LocalJSONCoder.encode(adminIds)
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCountData = LocalJSONCoder.encode(unreadCount)
        self.createdAt = createdAt
    }

    var participantIds: [String] {
        get { LocalJSONCoder.decode(participantIdsData, fallback: []) }
        set { participantIdsData = LocalJSONCoder.encode(newValue) }
    }

    var adminIds: [String] {
        get { LocalJSONCoder.decode(adminIdsData, fallback: []) }
        set { adminIdsData = LocalJSONCoder.encode(newValue) }
    }

    var unreadCount: [String: Int] {
        get { LocalJSONCoder.decode(unreadCountData, fallback: [:]) }
        set { unreadCountData = LocalJSONCoder.encode(newValue) }
    }
}

@Model
final class MessageEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var senderId: String
    var text: String
    var timestamp: Date
    var deliveryStatusRawValue: String
    var readByData: Data

    init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date = .init(),
        deliveryStatus: DeliveryStatus = .sending,
        readBy: [String] = []
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.deliveryStatusRawValue = deliveryStatus.rawValue
        self.readByData = LocalJSONCoder.encode(readBy)
    }

    var deliveryStatus: DeliveryStatus {
        get { DeliveryStatus(rawValue: deliveryStatusRawValue) ?? .sending }
        set { deliveryStatusRawValue = newValue.rawValue }
    }

    var readBy: [String] {
        get { LocalJSONCoder.decode(readByData, fallback: []) }
        set { readByData = LocalJSONCoder.encode(newValue) }
    }
}

enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    case sending
    case sent
    case delivered
    case read
}

private enum LocalJSONCoder {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data, fallback: T) -> T {
        (try? decoder.decode(T.self, from: data)) ?? fallback
    }
}
