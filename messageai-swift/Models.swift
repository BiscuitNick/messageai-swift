//
//  Models.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import SwiftData
import SwiftUI

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

    // Priority metadata
    var priorityScore: Int?
    var priorityLabel: String?
    var priorityRationale: String?
    var priorityAnalyzedAt: Date?

    init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date = .init(),
        deliveryStatus: DeliveryStatus = .sending,
        readReceipts: [String: Date] = [:],
        updatedAt: Date = .init(),
        priorityScore: Int? = nil,
        priorityLabel: String? = nil,
        priorityRationale: String? = nil,
        priorityAnalyzedAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.deliveryStatusRawValue = deliveryStatus.rawValue
        self.readByData = LocalJSONCoder.encode(readReceipts)
        self.updatedAt = updatedAt
        self.priorityScore = priorityScore
        self.priorityLabel = priorityLabel
        self.priorityRationale = priorityRationale
        self.priorityAnalyzedAt = priorityAnalyzedAt
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

    var priority: PriorityLevel {
        get {
            guard let label = priorityLabel else { return .medium }
            return PriorityLevel(rawValue: label) ?? .medium
        }
        set {
            priorityLabel = newValue.rawValue
        }
    }

    var hasPriorityData: Bool {
        priorityAnalyzedAt != nil
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

enum PriorityLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case urgent
    case critical

    var displayLabel: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "⚪️"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .urgent: return "🔴"
        case .critical: return "🔥"
        }
    }

    var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        case .critical: return 4
        }
    }
}

extension UserEntity {
    var presenceStatus: PresenceStatus {
        PresenceStatus.status(isOnline: isOnline, lastSeen: lastSeen)
    }
}

@Model
final class ThreadSummaryEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var summary: String
    var keyPointsData: Data
    var generatedAt: Date
    var messageCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        summary: String,
        keyPoints: [String],
        generatedAt: Date,
        messageCount: Int,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.summary = summary
        self.keyPointsData = LocalJSONCoder.encode(keyPoints)
        self.generatedAt = generatedAt
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var keyPoints: [String] {
        get { LocalJSONCoder.decode(keyPointsData, fallback: []) }
        set { keyPointsData = LocalJSONCoder.encode(newValue) }
    }
}

@Model
final class ActionItemEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var task: String
    var assignedTo: String?
    var dueDate: Date?
    var priorityRawValue: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        conversationId: String,
        task: String,
        assignedTo: String? = nil,
        dueDate: Date? = nil,
        priority: ActionItemPriority = .medium,
        status: ActionItemStatus = .pending,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.task = task
        self.assignedTo = assignedTo
        self.dueDate = dueDate
        self.priorityRawValue = priority.rawValue
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var priority: ActionItemPriority {
        get { ActionItemPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    var status: ActionItemStatus {
        get { ActionItemStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class SearchResultEntity {
    @Attribute(.unique) var id: String
    var query: String
    var conversationId: String
    var messageId: String
    var snippet: String
    var rank: Int
    var timestamp: Date
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        query: String,
        conversationId: String,
        messageId: String,
        snippet: String,
        rank: Int,
        timestamp: Date,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.messageId = messageId
        self.snippet = snippet
        self.rank = rank
        self.timestamp = timestamp
        self.query = query
        self.createdAt = createdAt
    }
}

@Model
final class RecentQueryEntity {
    @Attribute(.unique) var id: String
    var query: String
    var searchedAt: Date
    var resultCount: Int

    init(
        id: String = UUID().uuidString,
        query: String,
        searchedAt: Date = .init(),
        resultCount: Int = 0
    ) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
        self.resultCount = resultCount
    }
}

@Model
final class DecisionEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var decisionText: String
    var contextSummary: String
    var participantIdsData: Data
    var decidedAt: Date
    var followUpStatusRawValue: String
    var confidenceScore: Double
    var reminderDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        decisionText: String,
        contextSummary: String,
        participantIds: [String],
        decidedAt: Date,
        followUpStatus: DecisionFollowUpStatus = .pending,
        confidenceScore: Double,
        reminderDate: Date? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.decisionText = decisionText
        self.contextSummary = contextSummary
        self.participantIdsData = LocalJSONCoder.encode(participantIds)
        self.decidedAt = decidedAt
        self.followUpStatusRawValue = followUpStatus.rawValue
        self.confidenceScore = confidenceScore
        self.reminderDate = reminderDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var participantIds: [String] {
        get {
            if let ids = try? LocalJSONCoder.decoder.decode([String].self, from: participantIdsData) {
                return ids
            }
            return []
        }
        set {
            participantIdsData = LocalJSONCoder.encode(newValue)
        }
    }

    var followUpStatus: DecisionFollowUpStatus {
        get { DecisionFollowUpStatus(rawValue: followUpStatusRawValue) ?? .pending }
        set { followUpStatusRawValue = newValue.rawValue }
    }
}

enum DecisionFollowUpStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case cancelled

    var displayLabel: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
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
