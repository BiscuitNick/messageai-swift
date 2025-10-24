//
//  AIModels.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-23.
//

import Foundation

// MARK: - Thread Summarization DTOs

struct ThreadSummaryResponse: Codable {
    let summary: String
    let keyPoints: [String]
    let conversationId: String
    let timestamp: Date
    let messageCount: Int

    enum CodingKeys: String, CodingKey {
        case summary
        case keyPoints = "key_points"
        case conversationId = "conversation_id"
        case timestamp
        case messageCount = "message_count"
    }
}

// MARK: - Action Items DTOs

struct ActionItem: Codable, Identifiable {
    let id: String
    let description: String
    let assignedTo: String?
    let dueDate: Date?
    let priority: ActionItemPriority
    let status: ActionItemStatus
    let conversationId: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case assignedTo = "assigned_to"
        case dueDate = "due_date"
        case priority
        case status
        case conversationId = "conversation_id"
        case createdAt = "created_at"
    }
}

enum ActionItemPriority: String, Codable {
    case low
    case medium
    case high
    case urgent
}

enum ActionItemStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

struct ActionItemsResponse: Codable {
    let items: [ActionItem]
    let conversationId: String
    let extractedAt: Date

    enum CodingKeys: String, CodingKey {
        case items
        case conversationId = "conversation_id"
        case extractedAt = "extracted_at"
    }
}

// MARK: - Smart Search DTOs

struct SearchResult: Codable, Identifiable {
    let id: String
    let conversationId: String
    let messageId: String
    let snippet: String
    let relevanceScore: Double
    let timestamp: Date
    let participantNames: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case snippet
        case relevanceScore = "relevance_score"
        case timestamp
        case participantNames = "participant_names"
    }
}

struct SmartSearchResponse: Codable {
    let results: [SearchResult]
    let query: String
    let totalResults: Int
    let searchedAt: Date

    enum CodingKeys: String, CodingKey {
        case results
        case query
        case totalResults = "total_results"
        case searchedAt = "searched_at"
    }
}

// MARK: - Priority Detection DTOs

enum MessagePriority: String, Codable {
    case low
    case normal
    case high
    case urgent
}

struct PriorityUpdate: Codable {
    let messageId: String
    let conversationId: String
    let priority: MessagePriority
    let confidence: Double
    let reasoning: String?
    let detectedAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case priority
        case confidence
        case reasoning
        case detectedAt = "detected_at"
    }
}

struct PriorityUpdateResponse: Codable {
    let updates: [PriorityUpdate]
    let processedAt: Date

    enum CodingKeys: String, CodingKey {
        case updates
        case processedAt = "processed_at"
    }
}

// MARK: - Decision Tracking DTOs

struct Decision: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let conversationId: String
    let decidedBy: [String]
    let status: DecisionStatus
    let relatedActionItems: [String]
    let createdAt: Date
    let deadline: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case conversationId = "conversation_id"
        case decidedBy = "decided_by"
        case status
        case relatedActionItems = "related_action_items"
        case createdAt = "created_at"
        case deadline
    }
}

enum DecisionStatus: String, Codable {
    case proposed
    case approved
    case implemented
    case revisiting
    case cancelled
}

struct DecisionsResponse: Codable {
    let decisions: [Decision]
    let conversationId: String
    let trackedAt: Date

    enum CodingKeys: String, CodingKey {
        case decisions
        case conversationId = "conversation_id"
        case trackedAt = "tracked_at"
    }
}

struct TrackedDecisionsResponse: Codable {
    let analyzed: Int
    let persisted: Int
    let skipped: Int
    let conversationId: String

    enum CodingKeys: String, CodingKey {
        case analyzed
        case persisted
        case skipped
        case conversationId = "conversation_id"
    }
}

// MARK: - Meeting Suggestions DTOs

struct MeetingSuggestion: Codable, Identifiable {
    let id: String
    let proposedTimes: [ProposedTime]
    let conversationId: String
    let participants: [String]
    let reason: String
    let confidence: Double
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case proposedTimes = "proposed_times"
        case conversationId = "conversation_id"
        case participants
        case reason
        case confidence
        case generatedAt = "generated_at"
    }
}

struct ProposedTime: Codable, Identifiable {
    let id: String
    let startTime: Date
    let endTime: Date
    let timezone: String
    let availabilityScore: Double

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case timezone
        case availabilityScore = "availability_score"
    }
}

struct MeetingSuggestionsResponse: Codable {
    let suggestions: [MeetingSuggestion]
    let conversationId: String
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case suggestions
        case conversationId = "conversation_id"
        case generatedAt = "generated_at"
    }
}

// MARK: - Scheduling Intent DTOs

struct SchedulingIntent: Codable {
    let messageId: String
    let conversationId: String
    let detectedIntent: String
    let confidence: Double
    let suggestedAction: String?
    let detectedAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case detectedIntent = "detected_intent"
        case confidence
        case suggestedAction = "suggested_action"
        case detectedAt = "detected_at"
    }
}

struct SchedulingIntentResponse: Codable {
    let intent: SchedulingIntent
    let shouldShowSuggestions: Bool

    enum CodingKeys: String, CodingKey {
        case intent
        case shouldShowSuggestions = "should_show_suggestions"
    }
}

// MARK: - Proactive Coordination DTOs

struct ProactiveInsight: Codable, Identifiable {
    let id: String
    let type: InsightType
    let title: String
    let description: String
    let actionable: Bool
    let conversationIds: [String]
    let priority: MessagePriority
    let generatedAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case actionable
        case conversationIds = "conversation_ids"
        case priority
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
    }
}

enum InsightType: String, Codable {
    case unresolvedActionItem = "unresolved_action_item"
    case staleDecision = "stale_decision"
    case upcomingDeadline = "upcoming_deadline"
    case schedulingConflict = "scheduling_conflict"
    case blockedProgress = "blocked_progress"
}

struct ProactiveInsightsResponse: Codable {
    let insights: [ProactiveInsight]
    let generatedAt: Date
    let nextUpdateAt: Date

    enum CodingKeys: String, CodingKey {
        case insights
        case generatedAt = "generated_at"
        case nextUpdateAt = "next_update_at"
    }
}

// MARK: - Generic AI Response Wrapper

struct AIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case success
        case data
        case error
        case timestamp
    }
}
