//
//  CoordinationInsightEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-24.
//

import XCTest
import SwiftData
@testable import messageai_swift

final class CoordinationInsightEntityTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            CoordinationInsightEntity.self,
            ProactiveAlertEntity.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - Initialization Tests

    func testCoordinationInsightEntityInitialization() throws {
        let generatedAt = Date()
        let expiresAt = Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            summary: "Team coordination looking good",
            overallHealth: .good,
            generatedAt: generatedAt,
            expiresAt: expiresAt
        )

        XCTAssertEqual(insight.conversationId, "conv-123")
        XCTAssertEqual(insight.teamId, "team-1")
        XCTAssertEqual(insight.summary, "Team coordination looking good")
        XCTAssertEqual(insight.overallHealth, .good)
        XCTAssertEqual(insight.generatedAt, generatedAt)
        XCTAssertEqual(insight.expiresAt, expiresAt)
        XCTAssertTrue(insight.actionItems.isEmpty)
        XCTAssertTrue(insight.staleDecisions.isEmpty)
        XCTAssertFalse(insight.hasIssues)
    }

    func testCoordinationInsightWithActionItems() throws {
        let actionItems = [
            CoordinationActionItem(
                description: "Complete report",
                assignee: "user-1",
                deadline: "Friday",
                status: "unresolved"
            )
        ]

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            actionItems: actionItems,
            summary: "Action items pending",
            overallHealth: .attention_needed,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )

        XCTAssertEqual(insight.actionItems.count, 1)
        XCTAssertEqual(insight.actionItems.first?.description, "Complete report")
        XCTAssertEqual(insight.actionItems.first?.assignee, "user-1")
        XCTAssertTrue(insight.hasIssues)
        XCTAssertTrue(insight.needsAttention)
    }

    func testCoordinationInsightWithBlockers() throws {
        let blockers = [
            Blocker(description: "Waiting for API access", blockedBy: "IT department")
        ]

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            blockers: blockers,
            summary: "Blocked on IT",
            overallHealth: .critical,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )

        XCTAssertEqual(insight.blockers.count, 1)
        XCTAssertEqual(insight.blockers.first?.description, "Waiting for API access")
        XCTAssertEqual(insight.blockers.first?.blockedBy, "IT department")
        XCTAssertEqual(insight.overallHealth, .critical)
        XCTAssertTrue(insight.hasIssues)
    }

    // MARK: - Expiry Tests

    func testCoordinationInsightExpiry() throws {
        let expiredDate = Date().addingTimeInterval(-1 * 24 * 60 * 60) // 1 day ago
        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            summary: "Expired insight",
            generatedAt: Date().addingTimeInterval(-8 * 24 * 60 * 60),
            expiresAt: expiredDate
        )

        XCTAssertTrue(insight.isExpired)
    }

    func testCoordinationInsightNotExpired() throws {
        let futureDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            summary: "Active insight",
            generatedAt: Date(),
            expiresAt: futureDate
        )

        XCTAssertFalse(insight.isExpired)
    }

    // MARK: - Encoding/Decoding Tests

    func testActionItemsEncodeDecode() throws {
        let actionItems = [
            CoordinationActionItem(
                description: "Task 1",
                assignee: "user-1",
                deadline: "Monday",
                status: "pending"
            ),
            CoordinationActionItem(
                description: "Task 2",
                assignee: nil,
                deadline: nil,
                status: "unresolved"
            )
        ]

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            actionItems: actionItems,
            summary: "Test",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )

        modelContext.insert(insight)
        try modelContext.save()

        // Fetch and verify
        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            predicate: #Predicate { $0.conversationId == "conv-123" }
        )
        let fetchedInsights = try modelContext.fetch(descriptor)

        XCTAssertEqual(fetchedInsights.count, 1)
        XCTAssertEqual(fetchedInsights.first?.actionItems.count, 2)
        XCTAssertEqual(fetchedInsights.first?.actionItems.first?.description, "Task 1")
        XCTAssertEqual(fetchedInsights.first?.actionItems.first?.assignee, "user-1")
    }

    func testStaleDecisionsEncodeDecode() throws {
        let staleDecisions = [
            StaleDecision(
                topic: "Frontend framework choice",
                lastMentioned: "3 days ago",
                reason: "No follow-up action"
            )
        ]

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            staleDecisions: staleDecisions,
            summary: "Stale decision needs attention",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )

        modelContext.insert(insight)
        try modelContext.save()

        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            predicate: #Predicate { $0.conversationId == "conv-123" }
        )
        let fetchedInsights = try modelContext.fetch(descriptor)

        XCTAssertEqual(fetchedInsights.first?.staleDecisions.count, 1)
        XCTAssertEqual(fetchedInsights.first?.staleDecisions.first?.topic, "Frontend framework choice")
    }

    func testSchedulingConflictsEncodeDecode() throws {
        let conflicts = [
            SchedulingConflict(
                description: "Tuesday 2pm conflict",
                participants: ["user-1", "user-2", "user-3"]
            )
        ]

        let insight = CoordinationInsightEntity(
            conversationId: "conv-123",
            teamId: "team-1",
            schedulingConflicts: conflicts,
            summary: "Scheduling issues",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )

        modelContext.insert(insight)
        try modelContext.save()

        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            predicate: #Predicate { $0.conversationId == "conv-123" }
        )
        let fetchedInsights = try modelContext.fetch(descriptor)

        XCTAssertEqual(fetchedInsights.first?.schedulingConflicts.count, 1)
        XCTAssertEqual(fetchedInsights.first?.schedulingConflicts.first?.participants.count, 3)
    }

    // MARK: - ProactiveAlertEntity Tests

    func testProactiveAlertEntityInitialization() throws {
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 1 day

        let alert = ProactiveAlertEntity(
            conversationId: "conv-123",
            alertType: "action_item",
            title: "Action Item Overdue",
            message: "The report is overdue",
            severity: .high,
            expiresAt: expiresAt
        )

        XCTAssertEqual(alert.conversationId, "conv-123")
        XCTAssertEqual(alert.alertType, "action_item")
        XCTAssertEqual(alert.title, "Action Item Overdue")
        XCTAssertEqual(alert.severity, .high)
        XCTAssertFalse(alert.isRead)
        XCTAssertFalse(alert.isDismissed)
        XCTAssertTrue(alert.isActive)
    }

    func testProactiveAlertExpiry() throws {
        let expiredDate = Date().addingTimeInterval(-1 * 60 * 60) // 1 hour ago

        let alert = ProactiveAlertEntity(
            conversationId: "conv-123",
            alertType: "blocker",
            title: "Blocker Alert",
            message: "Team is blocked",
            expiresAt: expiredDate
        )

        XCTAssertTrue(alert.isExpired)
        XCTAssertFalse(alert.isActive)
    }

    func testProactiveAlertDismissal() throws {
        let alert = ProactiveAlertEntity(
            conversationId: "conv-123",
            alertType: "scheduling_conflict",
            title: "Scheduling Conflict",
            message: "Cannot find time to meet",
            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
        )

        XCTAssertTrue(alert.isActive)

        alert.isDismissed = true
        alert.dismissedAt = Date()

        XCTAssertFalse(alert.isActive)
    }

    func testProactiveAlertPersistence() throws {
        let alert = ProactiveAlertEntity(
            conversationId: "conv-123",
            alertType: "stale_decision",
            title: "Decision Needs Follow-up",
            message: "React framework decision from 3 days ago",
            severity: .medium,
            relatedInsightId: "insight-456",
            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
        )

        modelContext.insert(alert)
        try modelContext.save()

        let descriptor = FetchDescriptor<ProactiveAlertEntity>(
            predicate: #Predicate { $0.conversationId == "conv-123" }
        )
        let fetchedAlerts = try modelContext.fetch(descriptor)

        XCTAssertEqual(fetchedAlerts.count, 1)
        XCTAssertEqual(fetchedAlerts.first?.alertType, "stale_decision")
        XCTAssertEqual(fetchedAlerts.first?.severity, .medium)
        XCTAssertEqual(fetchedAlerts.first?.relatedInsightId, "insight-456")
    }

    // MARK: - Health Status Tests

    func testCoordinationHealthDisplayProperties() throws {
        XCTAssertEqual(CoordinationHealth.good.displayLabel, "Good")
        XCTAssertEqual(CoordinationHealth.attention_needed.displayLabel, "Needs Attention")
        XCTAssertEqual(CoordinationHealth.critical.displayLabel, "Critical")

        XCTAssertEqual(CoordinationHealth.good.emoji, "✅")
        XCTAssertEqual(CoordinationHealth.attention_needed.emoji, "⚠️")
        XCTAssertEqual(CoordinationHealth.critical.emoji, "🚨")
    }

    func testAlertSeverityDisplayProperties() throws {
        XCTAssertEqual(AlertSeverity.low.displayLabel, "Low")
        XCTAssertEqual(AlertSeverity.medium.displayLabel, "Medium")
        XCTAssertEqual(AlertSeverity.high.displayLabel, "High")
        XCTAssertEqual(AlertSeverity.critical.displayLabel, "Critical")

        XCTAssertEqual(AlertSeverity.low.emoji, "ℹ️")
        XCTAssertEqual(AlertSeverity.critical.emoji, "🚨")
    }
}
