//
//  ThreadSummaryEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

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
    var expiresAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        summary: String,
        keyPoints: [String],
        generatedAt: Date,
        messageCount: Int,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.summary = summary
        self.keyPointsData = LocalJSONCoder.encode(keyPoints)
        self.generatedAt = generatedAt
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        // Default TTL: 24 hours for summaries
        self.expiresAt = expiresAt ?? Date().addingTimeInterval(24 * 60 * 60)
    }

    var keyPoints: [String] {
        get { LocalJSONCoder.decode(keyPointsData, fallback: []) }
        set { keyPointsData = LocalJSONCoder.encode(newValue) }
    }

    var isExpired: Bool {
        Date() > expiresAt
    }
}
