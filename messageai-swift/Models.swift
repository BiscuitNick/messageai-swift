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
final class BotEntity {
    @Attribute(.unique) var id: String
    var name: String
    var botDescription: String
    var avatarURL: String
    var category: String
    var capabilitiesData: Data
    var model: String
    var systemPrompt: String
    var toolsData: Data
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        description: String,
        avatarURL: String,
        category: String = "general",
        capabilities: [String] = [],
        model: String = "gemini-1.5-flash",
        systemPrompt: String = "",
        tools: [String] = [],
        isActive: Bool = true,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.botDescription = description
        self.avatarURL = avatarURL
        self.category = category
        self.capabilitiesData = LocalJSONCoder.encode(capabilities)
        self.model = model
        self.systemPrompt = systemPrompt
        self.toolsData = LocalJSONCoder.encode(tools)
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var capabilities: [String] {
        get { LocalJSONCoder.decode(capabilitiesData, fallback: []) }
        set { capabilitiesData = LocalJSONCoder.encode(newValue) }
    }

    var tools: [String] {
        get { LocalJSONCoder.decode(toolsData, fallback: []) }
        set { toolsData = LocalJSONCoder.encode(newValue) }
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
    var lastSenderId: String?
    var unreadCountData: Data
    var lastInteractionByUserData: Data = LocalJSONCoder.encode([String: Date]())
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        participantIds: [String],
        isGroup: Bool = false,
        groupName: String? = nil,
        groupPictureURL: String? = nil,
        adminIds: [String] = [],
        lastMessage: String? = nil,
        lastMessageTimestamp: Date? = nil,
        lastSenderId: String? = nil,
        unreadCount: [String: Int] = [:],
        lastInteractionByUser: [String: Date] = [:],
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.participantIdsData = LocalJSONCoder.encode(participantIds)
        self.isGroup = isGroup
        self.groupName = groupName
        self.groupPictureURL = groupPictureURL
        self.adminIdsData = LocalJSONCoder.encode(adminIds)
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.lastSenderId = lastSenderId
        self.unreadCountData = LocalJSONCoder.encode(unreadCount)
        self.lastInteractionByUserData = LocalJSONCoder.encode(lastInteractionByUser)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

    var lastInteractionByUser: [String: Date] {
        get { LocalJSONCoder.decode(lastInteractionByUserData, fallback: [:]) }
        set { lastInteractionByUserData = LocalJSONCoder.encode(newValue) }
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
    var updatedAt: Date

    init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date = .init(),
        deliveryStatus: DeliveryStatus = .sending,
        readReceipts: [String: Date] = [:],
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.deliveryStatusRawValue = deliveryStatus.rawValue
        self.readByData = LocalJSONCoder.encode(readReceipts)
        self.updatedAt = updatedAt
    }

    var deliveryStatus: DeliveryStatus {
        get { DeliveryStatus(rawValue: deliveryStatusRawValue) ?? .sending }
        set { deliveryStatusRawValue = newValue.rawValue }
    }

    var readReceipts: [String: Date] {
        get {
            if let map = try? LocalJSONCoder.decoder.decode([String: Date].self, from: readByData) {
                return map
            }
            if let array = try? LocalJSONCoder.decoder.decode([String].self, from: readByData) {
                let fallbackDate = Date.distantPast
                return Dictionary(uniqueKeysWithValues: array.map { ($0, fallbackDate) })
            }
            return [:]
        }
        set {
            readByData = LocalJSONCoder.encode(newValue)
        }
    }

    var readBy: [String] {
        get { Array(readReceipts.keys) }
        set {
            let current = readReceipts
            var updated: [String: Date] = [:]
            let now = Date()
            for userId in newValue {
                updated[userId] = current[userId] ?? now
            }
            readReceipts = updated
        }
    }
}

enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    case sending
    case sent
    case delivered
    case read
}

enum PresenceStatus: String, Codable, CaseIterable, Sendable {
    case online
    case away
    case offline

    static func status(isOnline: Bool, lastSeen: Date, reference: Date = Date()) -> PresenceStatus {
        guard isOnline else { return .offline }
        let interval = max(reference.timeIntervalSince(lastSeen), 0)
        if interval <= 120 {
            return .online
        } else if interval <= 600 {
            return .away
        } else {
            return .offline
        }
    }
}

extension UserEntity {
    var presenceStatus: PresenceStatus {
        PresenceStatus.status(isOnline: isOnline, lastSeen: lastSeen)
    }
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
