//
//  ConversationEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

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
