//
//  ThreadSummaryEntity.swift
//  messageai-swift
//
//  Created by Claude Code on 10/23/25.
//

import Foundation
import SwiftData

@Model
final class ThreadSummaryEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var summary: String
    var messageCount: Int
    var createdAt: Date
    var generatedAt: Date
    var sourceMessageRange: String? // e.g., "msg-123...msg-456" for tracking which messages were summarized
    var isSaved: Bool // Whether user explicitly saved this summary

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        summary: String,
        messageCount: Int,
        createdAt: Date = Date(),
        generatedAt: Date,
        sourceMessageRange: String? = nil,
        isSaved: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.summary = summary
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.generatedAt = generatedAt
        self.sourceMessageRange = sourceMessageRange
        self.isSaved = isSaved
    }
}
