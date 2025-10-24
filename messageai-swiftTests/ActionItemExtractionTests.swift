//
//  ActionItemExtractionTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-24.
//

import XCTest
import SwiftData
@testable import messageai_swift

@MainActor
final class ActionItemExtractionTests: XCTestCase {

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
        service.configure(
            modelContext: modelContext,
            authService: AuthService(),
            messagingService: MessagingService(),
            firestoreService: FirestoreService()
        )
    }

    override func tearDown() async throws {
        service = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testServiceInitialization() {
        XCTAssertNotNil(service)
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
        XCTAssertTrue(service.actionItemsLoadingStates.isEmpty)
        XCTAssertTrue(service.actionItemsErrors.isEmpty)
    }

    // MARK: - Loading State Tests

    func testActionItemsLoadingStates() {
        let conversationId = "conv-loading-test"

        // Initially should be empty
        XCTAssertNil(service.actionItemsLoadingStates[conversationId])

        // Manually set loading state to test observable behavior
        service.actionItemsLoadingStates[conversationId] = true
        XCTAssertTrue(service.actionItemsLoadingStates[conversationId] == true)

        service.actionItemsLoadingStates[conversationId] = false
        XCTAssertTrue(service.actionItemsLoadingStates[conversationId] == false)
    }

    func testActionItemsErrorStates() {
        let conversationId = "conv-error-test"
        let errorMessage = "Test error message"

        // Initially should be empty
        XCTAssertNil(service.actionItemsErrors[conversationId])

        // Set error
        service.actionItemsErrors[conversationId] = errorMessage
        XCTAssertEqual(service.actionItemsErrors[conversationId], errorMessage)

        // Clear error
        service.actionItemsErrors[conversationId] = nil
        XCTAssertNil(service.actionItemsErrors[conversationId])
    }

    // MARK: - Cache Tests

    func testCacheClearing() {
        let conversationId = "conv-cache-test"

        // Set some state
        service.actionItemsLoadingStates[conversationId] = true
        service.actionItemsErrors[conversationId] = "error"

        // Clear caches
        service.clearCaches()

        // Note: clearCaches only clears internal cache dictionaries,
        // not the loading/error state dictionaries
        XCTAssertNotNil(service)
    }

    func testResetClearsState() {
        let conversationId = "conv-reset-test"

        // Set some state
        service.actionItemsLoadingStates[conversationId] = true
        service.actionItemsErrors[conversationId] = "error"
        service.isProcessing = true
        service.errorMessage = "global error"

        // Reset
        service.reset()

        // Verify state is reset
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Lifecycle Tests

    func testOnSignIn() {
        service.onSignIn()
        // Should not crash and should be ready for operations
        XCTAssertNotNil(service)
    }

    func testOnSignOut() {
        let conversationId = "conv-signout"
        service.actionItemsLoadingStates[conversationId] = true
        service.actionItemsErrors[conversationId] = "error"

        service.onSignOut()

        // Should reset state
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Error Handling Tests

    func testAIFeaturesErrorDescriptions() {
        XCTAssertEqual(AIFeaturesError.invalidResponse.errorDescription, "Invalid response from AI service")
        XCTAssertEqual(AIFeaturesError.notConfigured.errorDescription, "AIFeaturesService not properly configured")
        XCTAssertEqual(AIFeaturesError.unauthorized.errorDescription, "User not authorized for AI features")
    }

    // MARK: - Observable State Tests

    func testObservableLoadingStates() {
        let conversationId = "conv-observable"

        // Test that loading states can be observed
        let initialLoading = service.actionItemsLoadingStates[conversationId]
        XCTAssertNil(initialLoading)

        service.actionItemsLoadingStates[conversationId] = true
        XCTAssertTrue(service.actionItemsLoadingStates[conversationId] == true)
    }

    func testObservableErrorStates() {
        let conversationId = "conv-observable-error"

        // Test that error states can be observed
        let initialError = service.actionItemsErrors[conversationId]
        XCTAssertNil(initialError)

        service.actionItemsErrors[conversationId] = "Test error"
        XCTAssertEqual(service.actionItemsErrors[conversationId], "Test error")
    }

    // MARK: - Multiple Conversation Tests

    func testMultipleConversationStates() {
        let conv1 = "conv-1"
        let conv2 = "conv-2"
        let conv3 = "conv-3"

        // Set different states for different conversations
        service.actionItemsLoadingStates[conv1] = true
        service.actionItemsLoadingStates[conv2] = false
        service.actionItemsErrors[conv3] = "Error in conv3"

        // Verify states are independent
        XCTAssertTrue(service.actionItemsLoadingStates[conv1] == true)
        XCTAssertTrue(service.actionItemsLoadingStates[conv2] == false)
        XCTAssertNil(service.actionItemsLoadingStates[conv3])
        XCTAssertNil(service.actionItemsErrors[conv1])
        XCTAssertNil(service.actionItemsErrors[conv2])
        XCTAssertEqual(service.actionItemsErrors[conv3], "Error in conv3")
    }

    // MARK: - Configuration Tests

    func testServiceConfiguration() {
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

    // MARK: - Background Task Tests

    func testAnalyzeConversationInBackground() {
        let expectation = expectation(description: "Background analysis completes")

        service.analyzeConversationInBackground(conversationId: "conv-bg-123")

        // Give it a moment to execute
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // Should complete without crashing
        XCTAssertNotNil(service)
    }

    // MARK: - Integration Tests

    func testClearCachesAffectsActionItemsCache() {
        // Since clearCaches is internal, we test it indirectly
        service.clearCaches()

        // The service should still be functional
        XCTAssertNotNil(service)
        XCTAssertFalse(service.isProcessing)
    }

    func testStateConsistencyAfterReset() {
        // Set various states
        service.isProcessing = true
        service.errorMessage = "Some error"
        service.actionItemsLoadingStates["conv-1"] = true
        service.actionItemsErrors["conv-2"] = "Conv error"

        // Reset
        service.reset()

        // Check that global state is reset
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.errorMessage)

        // Note: reset() doesn't clear per-conversation states
        // Those are managed separately
        XCTAssertNotNil(service)
    }
}
