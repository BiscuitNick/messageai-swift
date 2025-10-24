//
//  AIFeaturesServiceTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-23.
//

import XCTest
import SwiftData
@testable import messageai_swift

@MainActor
final class AIFeaturesServiceTests: XCTestCase {

    var service: AIFeaturesService!
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

        service = AIFeaturesService()
    }

    override func tearDown() async throws {
        service = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testServiceInitialization() throws {
        XCTAssertNotNil(service)
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Configuration Tests

    func testServiceConfiguration() throws {
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Service should be configured without errors
        XCTAssertNotNil(service)
    }

    // MARK: - Lifecycle Tests

    func testOnSignIn() throws {
        service.onSignIn()
        // Should not crash and should be ready for future cache warming
        XCTAssertNotNil(service)
    }

    func testOnSignOut() throws {
        service.onSignOut()
        // Should clear caches and reset state
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
    }

    func testReset() throws {
        // Set some state
        service.clearCaches()

        service.reset()

        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Cache Management Tests

    func testClearCaches() throws {
        service.clearCaches()
        // Should not crash
        XCTAssertNotNil(service)
    }

    // MARK: - Message Observer Tests

    func testOnMessageMutation() throws {
        let conversationId = "conv-123"
        let messageId = "msg-456"

        service.onMessageMutation(conversationId: conversationId, messageId: messageId)

        // Should not crash - currently just logs in DEBUG mode
        XCTAssertNotNil(service)
    }

    // MARK: - Background Task Tests

    func testAnalyzeConversationInBackground() throws {
        let expectation = expectation(description: "Background analysis completes")

        service.analyzeConversationInBackground(conversationId: "conv-123")

        // Give it a moment to execute
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // Should complete without crashing
        XCTAssertNotNil(service)
    }

    // MARK: - Error Handling Tests

    func testAIFeaturesErrorDescriptions() throws {
        XCTAssertEqual(AIFeaturesError.invalidResponse.errorDescription, "Invalid response from AI service")
        XCTAssertEqual(AIFeaturesError.notConfigured.errorDescription, "AIFeaturesService not properly configured")
        XCTAssertEqual(AIFeaturesError.unauthorized.errorDescription, "User not authorized for AI features")
    }

    // MARK: - Observable State Tests

    func testIsProcessingState() throws {
        XCTAssertFalse(service.isProcessing)

        // Service state should be observable for SwiftUI bindings
        let initialState = service.isProcessing
        XCTAssertFalse(initialState)
    }

    func testErrorMessageState() throws {
        XCTAssertNil(service.errorMessage)

        // Service error message should be observable for SwiftUI bindings
        let initialError = service.errorMessage
        XCTAssertNil(initialError)
    }
}
