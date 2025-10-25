//
//  SearchEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

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
    var expiresAt: Date

    init(
        id: String = UUID().uuidString,
        query: String,
        conversationId: String,
        messageId: String,
        snippet: String,
        rank: Int,
        timestamp: Date,
        createdAt: Date = .init(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.messageId = messageId
        self.snippet = snippet
        self.rank = rank
        self.timestamp = timestamp
        self.query = query
        self.createdAt = createdAt
        // Default TTL: 1 hour for search results
        self.expiresAt = expiresAt ?? Date().addingTimeInterval(60 * 60)
    }

    var isExpired: Bool {
        Date() > expiresAt
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
