//
//  CoordinationEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Coordination Insights

@Model
final class CoordinationInsightEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var teamId: String
    var actionItemsData: Data
    var staleDecisionsData: Data
    var upcomingDeadlinesData: Data
    var schedulingConflictsData: Data
    var blockersData: Data
    var summary: String
    var overallHealthRawValue: String
    var generatedAt: Date
    var expiresAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        teamId: String,
        actionItems: [CoordinationActionItem] = [],
        staleDecisions: [StaleDecision] = [],
        upcomingDeadlines: [UpcomingDeadline] = [],
        schedulingConflicts: [SchedulingConflict] = [],
        blockers: [Blocker] = [],
        summary: String,
        overallHealth: CoordinationHealth = .good,
        generatedAt: Date,
        expiresAt: Date,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.teamId = teamId
        self.actionItemsData = LocalJSONCoder.encode(actionItems)
        self.staleDecisionsData = LocalJSONCoder.encode(staleDecisions)
        self.upcomingDeadlinesData = LocalJSONCoder.encode(upcomingDeadlines)
        self.schedulingConflictsData = LocalJSONCoder.encode(schedulingConflicts)
        self.blockersData = LocalJSONCoder.encode(blockers)
        self.summary = summary
        self.overallHealthRawValue = overallHealth.rawValue
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var actionItems: [CoordinationActionItem] {
        get { LocalJSONCoder.decode(actionItemsData, fallback: []) }
        set { actionItemsData = LocalJSONCoder.encode(newValue) }
    }

    var staleDecisions: [StaleDecision] {
        get { LocalJSONCoder.decode(staleDecisionsData, fallback: []) }
        set { staleDecisionsData = LocalJSONCoder.encode(newValue) }
    }

    var upcomingDeadlines: [UpcomingDeadline] {
        get { LocalJSONCoder.decode(upcomingDeadlinesData, fallback: []) }
        set { upcomingDeadlinesData = LocalJSONCoder.encode(newValue) }
    }

    var schedulingConflicts: [SchedulingConflict] {
        get { LocalJSONCoder.decode(schedulingConflictsData, fallback: []) }
        set { schedulingConflictsData = LocalJSONCoder.encode(newValue) }
    }

    var blockers: [Blocker] {
        get { LocalJSONCoder.decode(blockersData, fallback: []) }
        set { blockersData = LocalJSONCoder.encode(newValue) }
    }

    var overallHealth: CoordinationHealth {
        get { CoordinationHealth(rawValue: overallHealthRawValue) ?? .good }
        set { overallHealthRawValue = newValue.rawValue }
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var hasIssues: Bool {
        !actionItems.isEmpty || !staleDecisions.isEmpty || !blockers.isEmpty || !schedulingConflicts.isEmpty
    }

    var needsAttention: Bool {
        overallHealth != .good && hasIssues
    }
}

@Model
final class ProactiveAlertEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var alertType: String
    var title: String
    var message: String
    var severityRawValue: String
    var relatedInsightId: String?
    var isRead: Bool
    var isDismissed: Bool
    var createdAt: Date
    var expiresAt: Date
    var dismissedAt: Date?
    var readAt: Date?

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        alertType: String,
        title: String,
        message: String,
        severity: AlertSeverity = .medium,
        relatedInsightId: String? = nil,
        isRead: Bool = false,
        isDismissed: Bool = false,
        createdAt: Date = .init(),
        expiresAt: Date,
        dismissedAt: Date? = nil,
        readAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.alertType = alertType
        self.title = title
        self.message = message
        self.severityRawValue = severity.rawValue
        self.relatedInsightId = relatedInsightId
        self.isRead = isRead
        self.isDismissed = isDismissed
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.dismissedAt = dismissedAt
        self.readAt = readAt
    }

    var severity: AlertSeverity {
        get { AlertSeverity(rawValue: severityRawValue) ?? .medium }
        set { severityRawValue = newValue.rawValue }
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isActive: Bool {
        !isExpired && !isDismissed
    }
}

// MARK: - Coordination Supporting Types

struct CoordinationActionItem: Codable, Identifiable {
    var id: String { description }
    let description: String
    let assignee: String?
    let deadline: String?
    let status: String
}

struct StaleDecision: Codable, Identifiable {
    var id: String { topic }
    let topic: String
    let lastMentioned: String
    let reason: String
}

struct UpcomingDeadline: Codable, Identifiable {
    var id: String { description }
    let description: String
    let dueDate: String
    let urgency: String
}

struct SchedulingConflict: Codable, Identifiable {
    var id: String { description }
    let description: String
    let participants: [String]
}

struct Blocker: Codable, Identifiable {
    var id: String { description }
    let description: String
    let blockedBy: String?
}

enum CoordinationHealth: String, Codable, CaseIterable, Sendable {
    case good
    case attention_needed
    case critical

    var displayLabel: String {
        switch self {
        case .good: return "Good"
        case .attention_needed: return "Needs Attention"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .attention_needed: return .orange
        case .critical: return .red
        }
    }

    var emoji: String {
        switch self {
        case .good: return "✅"
        case .attention_needed: return "⚠️"
        case .critical: return "🚨"
        }
    }
}

enum AlertSeverity: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical

    var displayLabel: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    var emoji: String {
        switch self {
        case .low: return "ℹ️"
        case .medium: return "⚠️"
        case .high: return "‼️"
        case .critical: return "🚨"
        }
    }
}
