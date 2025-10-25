//
//  MessageEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

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

    // Scheduling intent metadata
    var schedulingIntent: String?
    var intentConfidence: Double?
    var intentAnalyzedAt: Date?
    var schedulingKeywordsData: Data = Data()

    init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date = .init(),
        deliveryState: MessageDeliveryState = .pending,
        readReceipts: [String: Date] = [:],
        updatedAt: Date = .init(),
        priorityScore: Int? = nil,
        priorityLabel: String? = nil,
        priorityRationale: String? = nil,
        priorityAnalyzedAt: Date? = nil,
        schedulingIntent: String? = nil,
        intentConfidence: Double? = nil,
        intentAnalyzedAt: Date? = nil,
        schedulingKeywords: [String] = []
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.deliveryStatusRawValue = deliveryState.rawValue
        self.readByData = LocalJSONCoder.encode(readReceipts)
        self.updatedAt = updatedAt
        self.priorityScore = priorityScore
        self.priorityLabel = priorityLabel
        self.priorityRationale = priorityRationale
        self.priorityAnalyzedAt = priorityAnalyzedAt
        self.schedulingIntent = schedulingIntent
        self.intentConfidence = intentConfidence
        self.intentAnalyzedAt = intentAnalyzedAt
        self.schedulingKeywordsData = LocalJSONCoder.encode(schedulingKeywords)
    }

    // New API using MessageDeliveryState
    var deliveryState: MessageDeliveryState {
        get {
            // Support legacy "sending" -> "pending" migration
            MessageDeliveryState(fromLegacy: deliveryStatusRawValue)
        }
        set {
            deliveryStatusRawValue = newValue.rawValue
        }
    }

    // Legacy API for backward compatibility
    @available(*, deprecated, message: "Use deliveryState instead")
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

    var schedulingKeywords: [String] {
        get { LocalJSONCoder.decode(schedulingKeywordsData, fallback: []) }
        set { schedulingKeywordsData = LocalJSONCoder.encode(newValue) }
    }

    var hasSchedulingData: Bool {
        intentAnalyzedAt != nil
    }
}
