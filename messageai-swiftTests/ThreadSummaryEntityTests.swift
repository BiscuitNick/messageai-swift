//
//  ThreadSummaryEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 10/23/25.
//

import XCTest
import SwiftData
@testable import messageai_swift

@MainActor
final class ThreadSummaryEntityTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUp() async throws {
        let schema = Schema([
            ThreadSummaryEntity.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - Initialization Tests

    func testThreadSummaryEntityInitialization() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Test summary",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        XCTAssertEqual(entity.conversationId, "conv-123")
        XCTAssertEqual(entity.summary, "Test summary")
        XCTAssertEqual(entity.messageCount, 10)
        XCTAssertTrue(entity.isSaved)
        XCTAssertNotNil(entity.id)
        XCTAssertNotNil(entity.createdAt)
        XCTAssertNotNil(entity.generatedAt)
    }

    func testThreadSummaryEntityWithOptionalFields() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Test summary",
            messageCount: 5,
            generatedAt: Date(),
            sourceMessageRange: "msg-1 to msg-5",
            isSaved: false
        )

        XCTAssertEqual(entity.sourceMessageRange, "msg-1 to msg-5")
        XCTAssertFalse(entity.isSaved)
    }

    // MARK: - Persistence Tests

    func testSaveThreadSummaryEntity() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Test summary",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(entity)
        try modelContext.save()

        // Verify entity was saved
        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.conversationId, "conv-123")
    }

    func testFetchSavedThreadSummary() throws {
        // Insert saved and unsaved summaries
        let savedEntity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Saved summary",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        let unsavedEntity = ThreadSummaryEntity(
            conversationId: "conv-456",
            summary: "Unsaved summary",
            messageCount: 5,
            generatedAt: Date(),
            isSaved: false
        )

        modelContext.insert(savedEntity)
        modelContext.insert(unsavedEntity)
        try modelContext.save()

        // Fetch only saved summaries
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate<ThreadSummaryEntity> { $0.isSaved == true }
        )
        let savedEntities = try modelContext.fetch(descriptor)

        XCTAssertEqual(savedEntities.count, 1)
        XCTAssertEqual(savedEntities.first?.conversationId, "conv-123")
    }

    func testFetchThreadSummaryForConversation() throws {
        // Insert multiple summaries
        let summary1 = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "First summary",
            messageCount: 10,
            generatedAt: Date().addingTimeInterval(-3600),
            isSaved: true
        )

        let summary2 = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Second summary",
            messageCount: 15,
            generatedAt: Date(),
            isSaved: true
        )

        let summary3 = ThreadSummaryEntity(
            conversationId: "conv-456",
            summary: "Other conversation",
            messageCount: 5,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(summary1)
        modelContext.insert(summary2)
        modelContext.insert(summary3)
        try modelContext.save()

        // Fetch summaries for specific conversation, sorted by creation date
        var descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate<ThreadSummaryEntity> {
                $0.conversationId == "conv-123" && $0.isSaved == true
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary, "Second summary")
    }

    func testDeleteThreadSummary() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Test summary",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(entity)
        try modelContext.save()

        // Delete the entity
        modelContext.delete(entity)
        try modelContext.save()

        // Verify entity was deleted
        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 0)
    }

    func testUpdateThreadSummary() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Original summary",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(entity)
        try modelContext.save()

        // Update the entity
        entity.summary = "Updated summary"
        entity.messageCount = 15
        try modelContext.save()

        // Verify entity was updated
        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary, "Updated summary")
        XCTAssertEqual(entities.first?.messageCount, 15)
    }

    // MARK: - Query Tests

    func testFetchMultipleSummariesForConversation() throws {
        let conversationId = "conv-123"

        // Create multiple summaries for the same conversation
        for i in 1...5 {
            let entity = ThreadSummaryEntity(
                conversationId: conversationId,
                summary: "Summary \(i)",
                messageCount: i * 10,
                generatedAt: Date().addingTimeInterval(Double(-i * 3600)),
                isSaved: true
            )
            modelContext.insert(entity)
        }

        try modelContext.save()

        // Fetch all summaries for the conversation
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate<ThreadSummaryEntity> {
                $0.conversationId == conversationId && $0.isSaved == true
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 5)
        XCTAssertEqual(entities.first?.summary, "Summary 1")
        XCTAssertEqual(entities.last?.summary, "Summary 5")
    }

    func testFetchSummariesAcrossMultipleConversations() throws {
        // Create summaries for multiple conversations
        for i in 1...3 {
            let entity = ThreadSummaryEntity(
                conversationId: "conv-\(i)",
                summary: "Summary for conversation \(i)",
                messageCount: i * 5,
                generatedAt: Date(),
                isSaved: true
            )
            modelContext.insert(entity)
        }

        try modelContext.save()

        // Fetch all saved summaries
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate<ThreadSummaryEntity> { $0.isSaved == true }
        )

        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 3)
    }

    // MARK: - Edge Cases

    func testEmptySummary() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "",
            messageCount: 0,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(entity)
        try modelContext.save()

        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary, "")
        XCTAssertEqual(entities.first?.messageCount, 0)
    }

    func testLargeSummary() throws {
        let largeSummary = String(repeating: "This is a test. ", count: 1000)

        let entity = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: largeSummary,
            messageCount: 500,
            generatedAt: Date(),
            isSaved: true
        )

        modelContext.insert(entity)
        try modelContext.save()

        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary.count, largeSummary.count)
    }

    func testUniqueIDGeneration() throws {
        let entity1 = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Summary 1",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        let entity2 = ThreadSummaryEntity(
            conversationId: "conv-123",
            summary: "Summary 2",
            messageCount: 10,
            generatedAt: Date(),
            isSaved: true
        )

        XCTAssertNotEqual(entity1.id, entity2.id)
    }
}
