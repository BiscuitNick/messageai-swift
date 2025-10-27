//
//  ThreadSummaryPersistenceTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-24.
//

import XCTest
import SwiftData
@testable import messageai_swift

@MainActor
final class ThreadSummaryPersistenceTests: XCTestCase {

    var service: AIFeaturesService!
    var modelContext: ModelContext!
    var networkMonitor: NetworkMonitor!

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

        networkMonitor = NetworkMonitor()
        service = AIFeaturesService()
        service.configure(
            modelContext: modelContext,
            authService: AuthCoordinator(),
            messagingService: MessagingService(),
            firestoreService: FirestoreService(),
            networkMonitor: networkMonitor
        )
    }

    override func tearDown() async throws {
        service = nil
        modelContext = nil
        networkMonitor = nil
        try await super.tearDown()
    }

    // MARK: - Save Tests

    func testSaveThreadSummary() throws {
        let conversationId = "conv-123"
        let summary = "Test summary text"
        let keyPoints = ["Point 1", "Point 2", "Point 3"]
        let generatedAt = Date()
        let messageCount = 42

        try service.saveThreadSummary(
            conversationId: conversationId,
            summary: summary,
            keyPoints: keyPoints,
            generatedAt: generatedAt,
            messageCount: messageCount
        )

        // Verify it was saved
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary, summary)
        XCTAssertEqual(entities.first?.keyPoints, keyPoints)
        XCTAssertEqual(entities.first?.messageCount, messageCount)
    }

    func testSaveThreadSummaryDeduplication() throws {
        let conversationId = "conv-123"

        // Save first summary
        try service.saveThreadSummary(
            conversationId: conversationId,
            summary: "First summary",
            keyPoints: ["Point 1"],
            generatedAt: Date(),
            messageCount: 10
        )

        // Save second summary for same conversation
        try service.saveThreadSummary(
            conversationId: conversationId,
            summary: "Updated summary",
            keyPoints: ["Point A", "Point B"],
            generatedAt: Date(),
            messageCount: 20
        )

        // Verify only one record exists
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )
        let entities = try modelContext.fetch(descriptor)

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.summary, "Updated summary")
        XCTAssertEqual(entities.first?.keyPoints.count, 2)
        XCTAssertEqual(entities.first?.messageCount, 20)
    }

    // MARK: - Fetch Tests

    func testFetchThreadSummary() throws {
        let conversationId = "conv-456"
        let summary = "Fetched summary"
        let keyPoints = ["A", "B", "C"]

        // Save a summary
        try service.saveThreadSummary(
            conversationId: conversationId,
            summary: summary,
            keyPoints: keyPoints,
            generatedAt: Date(),
            messageCount: 15
        )

        // Fetch it back
        let fetched = service.fetchThreadSummary(for: conversationId)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.summary, summary)
        XCTAssertEqual(fetched?.keyPoints, keyPoints)
        XCTAssertEqual(fetched?.conversationId, conversationId)
    }

    func testFetchNonexistentSummary() {
        let result = service.fetchThreadSummary(for: "nonexistent-id")
        XCTAssertNil(result)
    }

    // MARK: - Delete Tests

    func testDeleteThreadSummary() throws {
        let conversationId = "conv-789"

        // Save a summary
        try service.saveThreadSummary(
            conversationId: conversationId,
            summary: "To be deleted",
            keyPoints: ["Point"],
            generatedAt: Date(),
            messageCount: 5
        )

        // Verify it exists
        XCTAssertNotNil(service.fetchThreadSummary(for: conversationId))

        // Delete it
        try service.deleteThreadSummary(for: conversationId)

        // Verify it's gone
        XCTAssertNil(service.fetchThreadSummary(for: conversationId))
    }

    func testDeleteNonexistentSummary() throws {
        // Should not throw
        XCTAssertNoThrow(try service.deleteThreadSummary(for: "nonexistent-id"))
    }

    // MARK: - ThreadSummaryEntity Tests

    func testThreadSummaryEntityEncoding() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-encode",
            summary: "Test summary",
            keyPoints: ["Key 1", "Key 2"],
            generatedAt: Date(),
            messageCount: 25
        )

        XCTAssertEqual(entity.keyPoints.count, 2)
        XCTAssertEqual(entity.keyPoints[0], "Key 1")
        XCTAssertEqual(entity.keyPoints[1], "Key 2")
    }

    func testThreadSummaryEntityUpdate() throws {
        let entity = ThreadSummaryEntity(
            conversationId: "conv-update",
            summary: "Initial",
            keyPoints: ["A"],
            generatedAt: Date(),
            messageCount: 10
        )

        // Update key points
        entity.keyPoints = ["X", "Y", "Z"]

        XCTAssertEqual(entity.keyPoints.count, 3)
        XCTAssertEqual(entity.keyPoints[0], "X")
    }
}
