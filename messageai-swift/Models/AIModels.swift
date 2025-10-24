//
//  AIModels.swift
//  messageai-swift
//
//  Created by Claude Code on 10/23/25.
//

import Foundation

// MARK: - Message Priority

enum MessagePriority: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case urgent
}

// MARK: - Summary Response

struct SummaryResponse: Codable {
    let summary: String
    let conversationId: String
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case summary
        case conversationId
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        conversationId = try container.decode(String.self, forKey: .conversationId)

        // Handle timestamp from Firebase (can be seconds since epoch or Date)
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .generatedAt) {
            generatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            generatedAt = try? container.decode(Date.self, forKey: .generatedAt)
        }
    }
}

// MARK: - Action Items

struct ActionItem: Codable, Identifiable {
    let id: String
    let text: String
    let assignee: String?
    let dueDate: Date?
    let priority: MessagePriority
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case assignee
        case dueDate
        case priority
        case isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        assignee = try? container.decode(String.self, forKey: .assignee)
        priority = (try? container.decode(MessagePriority.self, forKey: .priority)) ?? .medium
        isCompleted = (try? container.decode(Bool.self, forKey: .isCompleted)) ?? false

        // Handle timestamp from Firebase
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .dueDate) {
            dueDate = Date(timeIntervalSince1970: timestamp)
        } else {
            dueDate = try? container.decode(Date.self, forKey: .dueDate)
        }
    }
}

struct ActionItemsResponse: Codable {
    let actionItems: [ActionItem]
    let conversationId: String
}

// MARK: - Search

struct SearchResult: Codable, Identifiable {
    let id: String
    let messageId: String
    let conversationId: String
    let text: String
    let snippet: String
    let relevanceScore: Double
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case messageId
        case conversationId
        case text
        case snippet
        case relevanceScore
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messageId = try container.decode(String.self, forKey: .messageId)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        text = try container.decode(String.self, forKey: .text)
        snippet = try container.decode(String.self, forKey: .snippet)
        relevanceScore = (try? container.decode(Double.self, forKey: .relevanceScore)) ?? 0.0

        // Handle timestamp from Firebase
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: timestamp)
        } else {
            timestamp = try? container.decode(Date.self, forKey: .timestamp)
        }
    }
}

struct SearchResponse: Codable {
    let results: [SearchResult]
    let query: String
}

// MARK: - Priority Updates

struct PriorityUpdateResponse: Codable {
    let success: Bool
    let messageId: String
    let priority: MessagePriority
}

// MARK: - Decisions

struct Decision: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let options: [DecisionOption]
    let recommendation: String?
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case options
        case recommendation
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        options = try container.decode([DecisionOption].self, forKey: .options)
        recommendation = try? container.decode(String.self, forKey: .recommendation)
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.0
    }
}

struct DecisionOption: Codable, Identifiable {
    let id: String
    let text: String
    let pros: [String]
    let cons: [String]
}

struct DecisionsResponse: Codable {
    let decisions: [Decision]
    let conversationId: String
}

// MARK: - Insights

struct Insight: Codable, Identifiable {
    let id: String
    let type: InsightType
    let title: String
    let description: String
    let actionable: Bool
    let conversationId: String?
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case actionable
        case conversationId
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = (try? container.decode(InsightType.self, forKey: .type)) ?? .general
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        actionable = (try? container.decode(Bool.self, forKey: .actionable)) ?? false
        conversationId = try? container.decode(String.self, forKey: .conversationId)

        // Handle timestamp from Firebase
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .generatedAt) {
            generatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            generatedAt = try? container.decode(Date.self, forKey: .generatedAt)
        }
    }
}

enum InsightType: String, Codable {
    case general
    case trend
    case recommendation
    case warning
    case opportunity
}

struct InsightsResponse: Codable {
    let insights: [Insight]
    let userId: String
}

// MARK: - Thread Summary

struct ThreadSummaryResponse: Codable {
    let summary: String
    let conversationId: String
    let messageCount: Int
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case summary
        case conversationId
        case messageCount
        case generatedAt
    }

    init(summary: String, conversationId: String, messageCount: Int, generatedAt: Date) {
        self.summary = summary
        self.conversationId = conversationId
        self.messageCount = messageCount
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        messageCount = try container.decode(Int.self, forKey: .messageCount)

        // Handle timestamp from Firebase (milliseconds since epoch)
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .generatedAt) {
            generatedAt = Date(timeIntervalSince1970: timestamp / 1000.0)
        } else {
            generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        }
    }
}
