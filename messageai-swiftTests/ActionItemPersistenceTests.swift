//
//  ActionItemPersistenceTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-24.
//

import XCTest
import SwiftData
@testable import messageai_swift

@MainActor
final class ActionItemPersistenceTests: XCTestCase {

    var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        // Set up in-memory SwiftData container for testing
        let schema = Schema([
            UserEntity.self,
            BotEntity.self,
            ConversationEntity.self,
            MessageEntity.self,
            ThreadSummaryEntity.self,
            ActionItemEntity.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(container)
    }

    override func tearDown() async throws {
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - Create Tests

    func testCreateActionItem() throws {
        let conversationId = "conv-123"
        let task = "Review pull request #42"
        let priority = ActionItemPriority.high
        let status = ActionItemStatus.pending

        let item = ActionItemEntity(
            id: UUID().uuidString,
            conversationId: conversationId,
            task: task,
            assignedTo: nil,
            dueDate: nil,
            priority: priority,
            status: status
        )

        modelContext.insert(item)
        try modelContext.save()

        // Verify it was saved
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        let items = try modelContext.fetch(descriptor)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.task, task)
        XCTAssertEqual(items.first?.priority, priority)
        XCTAssertEqual(items.first?.status, status)
    }

    func testCreateActionItemWithAllFields() throws {
        let conversationId = "conv-456"
        let task = "Deploy to production"
        let assignedTo = "user-123"
        let dueDate = Date().addingTimeInterval(86400) // Tomorrow
        let priority = ActionItemPriority.urgent
        let status = ActionItemStatus.inProgress

        let item = ActionItemEntity(
            id: UUID().uuidString,
            conversationId: conversationId,
            task: task,
            assignedTo: assignedTo,
            dueDate: dueDate,
            priority: priority,
            status: status
        )

        modelContext.insert(item)
        try modelContext.save()

        // Verify all fields
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        let items = try modelContext.fetch(descriptor)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.task, task)
        XCTAssertEqual(items.first?.assignedTo, assignedTo)
        XCTAssertNotNil(items.first?.dueDate)
        XCTAssertEqual(items.first?.priority, priority)
        XCTAssertEqual(items.first?.status, status)
    }

    // MARK: - Read Tests

    func testFetchActionItemsByConversation() throws {
        let conversationId = "conv-789"

        // Create multiple items
        for i in 1...3 {
            let item = ActionItemEntity(
                id: "item-\(i)",
                conversationId: conversationId,
                task: "Task \(i)",
                priority: .medium,
                status: .pending
            )
            modelContext.insert(item)
        }

        try modelContext.save()

        // Fetch items for conversation
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        let items = try modelContext.fetch(descriptor)

        XCTAssertEqual(items.count, 3)
    }

    func testFetchActionItemsByStatus() throws {
        let conversationId = "conv-status"

        // Create items with different statuses
        let pendingItem = ActionItemEntity(
            id: "pending-1",
            conversationId: conversationId,
            task: "Pending task",
            priority: .medium,
            status: .pending
        )
        let completedItem = ActionItemEntity(
            id: "completed-1",
            conversationId: conversationId,
            task: "Completed task",
            priority: .medium,
            status: .completed
        )

        modelContext.insert(pendingItem)
        modelContext.insert(completedItem)
        try modelContext.save()

        // Fetch only pending items
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == conversationId && $0.statusRawValue == "pending" }
        )
        let pendingItems = try modelContext.fetch(descriptor)

        XCTAssertEqual(pendingItems.count, 1)
        XCTAssertEqual(pendingItems.first?.task, "Pending task")
    }

    func testFetchActionItemsSortedByPriority() throws {
        let conversationId = "conv-priority"

        // Create items with different priorities
        let lowItem = ActionItemEntity(
            id: "low-1",
            conversationId: conversationId,
            task: "Low priority task",
            priority: .low,
            status: .pending
        )
        let urgentItem = ActionItemEntity(
            id: "urgent-1",
            conversationId: conversationId,
            task: "Urgent task",
            priority: .urgent,
            status: .pending
        )
        let mediumItem = ActionItemEntity(
            id: "medium-1",
            conversationId: conversationId,
            task: "Medium priority task",
            priority: .medium,
            status: .pending
        )

        modelContext.insert(lowItem)
        modelContext.insert(urgentItem)
        modelContext.insert(mediumItem)
        try modelContext.save()

        // Fetch sorted by priority descending
        var descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        descriptor.sortBy = [SortDescriptor(\ActionItemEntity.priorityRawValue, order: .reverse)]

        let items = try modelContext.fetch(descriptor)

        XCTAssertEqual(items.count, 3)
        // Urgent should be first (alphabetically "urgent" > "medium" > "low" in reverse)
        XCTAssertEqual(items[0].priority, .urgent)
    }

    // MARK: - Update Tests

    func testUpdateActionItemStatus() throws {
        let conversationId = "conv-update"
        let itemId = "item-update-1"

        let item = ActionItemEntity(
            id: itemId,
            conversationId: conversationId,
            task: "Update test",
            priority: .medium,
            status: .pending
        )

        modelContext.insert(item)
        try modelContext.save()

        // Update status
        item.status = .completed
        item.updatedAt = Date()
        try modelContext.save()

        // Verify update
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.id == itemId }
        )
        let updatedItems = try modelContext.fetch(descriptor)

        XCTAssertEqual(updatedItems.count, 1)
        XCTAssertEqual(updatedItems.first?.status, .completed)
    }

    func testUpdateActionItemFields() throws {
        let conversationId = "conv-update-fields"
        let itemId = "item-update-2"

        let item = ActionItemEntity(
            id: itemId,
            conversationId: conversationId,
            task: "Original task",
            priority: .low,
            status: .pending
        )

        modelContext.insert(item)
        try modelContext.save()

        // Update multiple fields
        item.task = "Updated task"
        item.priority = .high
        item.assignedTo = "user-456"
        item.dueDate = Date().addingTimeInterval(172800) // 2 days
        item.updatedAt = Date()
        try modelContext.save()

        // Verify updates
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.id == itemId }
        )
        let updatedItems = try modelContext.fetch(descriptor)

        XCTAssertEqual(updatedItems.first?.task, "Updated task")
        XCTAssertEqual(updatedItems.first?.priority, .high)
        XCTAssertEqual(updatedItems.first?.assignedTo, "user-456")
        XCTAssertNotNil(updatedItems.first?.dueDate)
    }

    // MARK: - Delete Tests

    func testDeleteActionItem() throws {
        let conversationId = "conv-delete"
        let itemId = "item-delete-1"

        let item = ActionItemEntity(
            id: itemId,
            conversationId: conversationId,
            task: "To be deleted",
            priority: .medium,
            status: .pending
        )

        modelContext.insert(item)
        try modelContext.save()

        // Verify it exists
        var descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.id == itemId }
        )
        var items = try modelContext.fetch(descriptor)
        XCTAssertEqual(items.count, 1)

        // Delete it
        modelContext.delete(item)
        try modelContext.save()

        // Verify it's gone
        items = try modelContext.fetch(descriptor)
        XCTAssertEqual(items.count, 0)
    }

    // MARK: - Enum Tests

    func testActionItemPriorityRawValues() {
        XCTAssertEqual(ActionItemPriority.low.rawValue, "low")
        XCTAssertEqual(ActionItemPriority.medium.rawValue, "medium")
        XCTAssertEqual(ActionItemPriority.high.rawValue, "high")
        XCTAssertEqual(ActionItemPriority.urgent.rawValue, "urgent")
    }

    func testActionItemStatusRawValues() {
        XCTAssertEqual(ActionItemStatus.pending.rawValue, "pending")
        XCTAssertEqual(ActionItemStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(ActionItemStatus.completed.rawValue, "completed")
        XCTAssertEqual(ActionItemStatus.cancelled.rawValue, "cancelled")
    }

    func testActionItemPriorityFromRawValue() {
        XCTAssertEqual(ActionItemPriority(rawValue: "low"), .low)
        XCTAssertEqual(ActionItemPriority(rawValue: "urgent"), .urgent)
        XCTAssertNil(ActionItemPriority(rawValue: "invalid"))
    }

    func testActionItemStatusFromRawValue() {
        XCTAssertEqual(ActionItemStatus(rawValue: "pending"), .pending)
        XCTAssertEqual(ActionItemStatus(rawValue: "in_progress"), .inProgress)
        XCTAssertNil(ActionItemStatus(rawValue: "invalid"))
    }

    // MARK: - Query Tests

    func testFetchMultipleConversations() throws {
        // Create items for different conversations
        let item1 = ActionItemEntity(
            id: "item-1",
            conversationId: "conv-1",
            task: "Task 1",
            priority: .medium,
            status: .pending
        )
        let item2 = ActionItemEntity(
            id: "item-2",
            conversationId: "conv-2",
            task: "Task 2",
            priority: .high,
            status: .completed
        )
        let item3 = ActionItemEntity(
            id: "item-3",
            conversationId: "conv-1",
            task: "Task 3",
            priority: .low,
            status: .pending
        )

        modelContext.insert(item1)
        modelContext.insert(item2)
        modelContext.insert(item3)
        try modelContext.save()

        // Fetch only conv-1 items
        let descriptor = FetchDescriptor<ActionItemEntity>(
            predicate: #Predicate { $0.conversationId == "conv-1" }
        )
        let conv1Items = try modelContext.fetch(descriptor)

        XCTAssertEqual(conv1Items.count, 2)
        XCTAssertTrue(conv1Items.allSatisfy { $0.conversationId == "conv-1" })
    }

    func testActionItemDisplayNames() {
        XCTAssertEqual(ActionItemPriority.low.displayName, "Low")
        XCTAssertEqual(ActionItemPriority.medium.displayName, "Medium")
        XCTAssertEqual(ActionItemPriority.high.displayName, "High")
        XCTAssertEqual(ActionItemPriority.urgent.displayName, "Urgent")

        XCTAssertEqual(ActionItemStatus.pending.displayName, "Pending")
        XCTAssertEqual(ActionItemStatus.inProgress.displayName, "In Progress")
        XCTAssertEqual(ActionItemStatus.completed.displayName, "Completed")
        XCTAssertEqual(ActionItemStatus.cancelled.displayName, "Cancelled")
    }
}
