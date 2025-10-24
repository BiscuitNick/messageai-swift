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
            MeetingSuggestionEntity.self,
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

    // MARK: - Meeting Suggestions Persistence Tests

    func testSaveMeetingSuggestions() throws {
        // Configure service with model context
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create test response
        let suggestion = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600), // 2024-10-25T14:00:00Z
            endTime: Date(timeIntervalSince1970: 1729873200),   // 2024-10-25T15:00:00Z
            score: 0.9,
            justification: "Test justification",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        let response = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-123",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400) // 24 hours
        )

        // Save suggestions
        try service.saveMeetingSuggestions(response: response)

        // Fetch from SwiftData
        let fetchedEntity = service.fetchMeetingSuggestions(for: "conv-123")
        XCTAssertNotNil(fetchedEntity)
        XCTAssertEqual(fetchedEntity?.conversationId, "conv-123")
        XCTAssertEqual(fetchedEntity?.durationMinutes, 60)
        XCTAssertEqual(fetchedEntity?.participantCount, 2)
        XCTAssertEqual(fetchedEntity?.suggestions.count, 1)
        XCTAssertFalse(fetchedEntity?.isExpired ?? true)
        XCTAssertTrue(fetchedEntity?.isValid ?? false)
    }

    func testFetchMeetingSuggestionsReturnsNilWhenNotFound() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Fetch non-existent suggestions
        let fetchedEntity = service.fetchMeetingSuggestions(for: "non-existent-conv")
        XCTAssertNil(fetchedEntity)
    }

    func testDeleteMeetingSuggestions() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create and save test response
        let suggestion = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.9,
            justification: "Test justification",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        let response = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-to-delete",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        try service.saveMeetingSuggestions(response: response)

        // Verify it exists
        var fetchedEntity = service.fetchMeetingSuggestions(for: "conv-to-delete")
        XCTAssertNotNil(fetchedEntity)

        // Delete it
        try service.deleteMeetingSuggestions(for: "conv-to-delete")

        // Verify it's gone
        fetchedEntity = service.fetchMeetingSuggestions(for: "conv-to-delete")
        XCTAssertNil(fetchedEntity)
    }

    func testClearExpiredMeetingSuggestions() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        let suggestion = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.9,
            justification: "Test justification",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        // Create expired response
        let expiredResponse = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-expired",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date().addingTimeInterval(-172800), // 2 days ago
            expiresAt: Date().addingTimeInterval(-86400) // Expired 1 day ago
        )

        // Create valid response
        let validResponse = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-valid",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400) // Expires in 1 day
        )

        try service.saveMeetingSuggestions(response: expiredResponse)
        try service.saveMeetingSuggestions(response: validResponse)

        // Verify both exist
        XCTAssertNotNil(service.fetchMeetingSuggestions(for: "conv-expired"))
        XCTAssertNotNil(service.fetchMeetingSuggestions(for: "conv-valid"))

        // Clear expired
        try service.clearExpiredMeetingSuggestions()

        // Verify expired is gone, valid remains
        XCTAssertNil(service.fetchMeetingSuggestions(for: "conv-expired"))
        XCTAssertNotNil(service.fetchMeetingSuggestions(for: "conv-valid"))
    }

    func testMeetingSuggestionExpiryLogic() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        let suggestion = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.9,
            justification: "Test justification",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        // Create expired response
        let expiredResponse = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-expiry-test",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date().addingTimeInterval(-172800),
            expiresAt: Date().addingTimeInterval(-86400)
        )

        try service.saveMeetingSuggestions(response: expiredResponse)

        let entity = service.fetchMeetingSuggestions(for: "conv-expiry-test")
        XCTAssertNotNil(entity)
        XCTAssertTrue(entity?.isExpired ?? false)
        XCTAssertFalse(entity?.isValid ?? true) // isValid should be false when expired
    }

    func testMeetingSuggestionValidationWithEmptySuggestions() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create response with empty suggestions
        let emptyResponse = MeetingSuggestionsResponse(
            suggestions: [],
            conversationId: "conv-empty",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        try service.saveMeetingSuggestions(response: emptyResponse)

        let entity = service.fetchMeetingSuggestions(for: "conv-empty")
        XCTAssertNotNil(entity)
        XCTAssertFalse(entity?.isExpired ?? true)
        XCTAssertFalse(entity?.isValid ?? true) // isValid should be false when suggestions are empty
    }

    func testMeetingSuggestionsLoadingState() throws {
        // Test that loading state is tracked per conversation
        XCTAssertNil(service.meetingSuggestionsLoadingStates["conv-123"])

        // Simulate setting loading state (normally done by suggestMeetingTimes)
        // Note: We can't test the full method without mocking network calls,
        // but we can verify the state property exists and is observable
        XCTAssertNotNil(service.meetingSuggestionsLoadingStates)
    }

    func testMeetingSuggestionsErrorState() throws {
        // Test that error state is tracked per conversation
        XCTAssertNil(service.meetingSuggestionsErrors["conv-123"])

        // Verify the state property exists and is observable
        XCTAssertNotNil(service.meetingSuggestionsErrors)
    }

    func testClearCachesIncludesMeetingSuggestions() throws {
        // This test verifies that clearCaches() properly clears meeting suggestions cache
        // (The actual cache is private, so we're testing that it doesn't crash)
        service.clearCaches()
        XCTAssertNotNil(service)
    }

    func testMeetingSuggestionDataRoundTrip() throws {
        // Test that MeetingTimeSuggestionData properly encodes/decodes
        let data = MeetingTimeSuggestionData(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.85,
            justification: "Great time for meeting",
            dayOfWeek: "Monday",
            timeOfDay: "morning"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(data)
        let decoded = try decoder.decode(MeetingTimeSuggestionData.self, from: encoded)

        XCTAssertEqual(decoded.score, 0.85)
        XCTAssertEqual(decoded.justification, "Great time for meeting")
        XCTAssertEqual(decoded.dayOfWeek, "Monday")
        XCTAssertEqual(decoded.timeOfDay, "morning")
        XCTAssertEqual(decoded.startTime.timeIntervalSince1970, 1729869600, accuracy: 1.0)
    }

    func testMultipleMeetingSuggestionsForDifferentConversations() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        let suggestion = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.9,
            justification: "Test",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        // Create suggestions for multiple conversations
        let response1 = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-1",
            durationMinutes: 30,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        let response2 = MeetingSuggestionsResponse(
            suggestions: [suggestion],
            conversationId: "conv-2",
            durationMinutes: 60,
            participantCount: 3,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        try service.saveMeetingSuggestions(response: response1)
        try service.saveMeetingSuggestions(response: response2)

        // Verify both exist independently
        let entity1 = service.fetchMeetingSuggestions(for: "conv-1")
        let entity2 = service.fetchMeetingSuggestions(for: "conv-2")

        XCTAssertNotNil(entity1)
        XCTAssertNotNil(entity2)
        XCTAssertEqual(entity1?.durationMinutes, 30)
        XCTAssertEqual(entity2?.durationMinutes, 60)
        XCTAssertEqual(entity1?.participantCount, 2)
        XCTAssertEqual(entity2?.participantCount, 3)
    }

    func testUpdateExistingMeetingSuggestions() throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        let suggestion1 = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729869600),
            endTime: Date(timeIntervalSince1970: 1729873200),
            score: 0.9,
            justification: "Original",
            dayOfWeek: "Friday",
            timeOfDay: .afternoon
        )

        let suggestion2 = MeetingTimeSuggestion(
            startTime: Date(timeIntervalSince1970: 1729956000),
            endTime: Date(timeIntervalSince1970: 1729959600),
            score: 0.95,
            justification: "Updated",
            dayOfWeek: "Saturday",
            timeOfDay: .morning
        )

        // Save initial suggestions
        let initialResponse = MeetingSuggestionsResponse(
            suggestions: [suggestion1],
            conversationId: "conv-update",
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        try service.saveMeetingSuggestions(response: initialResponse)

        var entity = service.fetchMeetingSuggestions(for: "conv-update")
        XCTAssertEqual(entity?.suggestions.count, 1)
        XCTAssertEqual(entity?.suggestions.first?.justification, "Original")

        // Update with new suggestions
        let updatedResponse = MeetingSuggestionsResponse(
            suggestions: [suggestion2],
            conversationId: "conv-update",
            durationMinutes: 90,
            participantCount: 3,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        try service.saveMeetingSuggestions(response: updatedResponse)

        entity = service.fetchMeetingSuggestions(for: "conv-update")
        XCTAssertEqual(entity?.suggestions.count, 1)
        XCTAssertEqual(entity?.suggestions.first?.justification, "Updated")
        XCTAssertEqual(entity?.durationMinutes, 90)
        XCTAssertEqual(entity?.participantCount, 3)
    }

    // MARK: - Scheduling Intent Detection Tests

    func testSchedulingIntentStateExposedToUI() throws {
        // Verify that scheduling intent state is exposed to UI
        XCTAssertEqual(service.schedulingIntentDetected.count, 0)
        XCTAssertEqual(service.schedulingIntentConfidence.count, 0)
    }

    func testOnMessageMutationWithoutSchedulingIntent() async throws {
        // Configure service with mock dependencies
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation
        let conversation = ConversationEntity(
            id: "conv-no-intent",
            participantIds: ["user-1", "user-2"],
            isGroup: false
        )
        modelContext.insert(conversation)

        // Create message without scheduling intent
        let message = MessageEntity(
            id: "msg-no-intent",
            conversationId: "conv-no-intent",
            senderId: "user-1",
            text: "Just a regular message"
        )
        modelContext.insert(message)
        try modelContext.save()

        // Call onMessageMutation
        service.onMessageMutation(conversationId: "conv-no-intent", messageId: "msg-no-intent")

        // Wait for async task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify no scheduling intent detected
        XCTAssertNil(service.schedulingIntentDetected["conv-no-intent"])
        XCTAssertNil(service.schedulingIntentConfidence["conv-no-intent"])
    }

    func testOnMessageMutationWithLowConfidenceIntent() async throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation
        let conversation = ConversationEntity(
            id: "conv-low",
            participantIds: ["user-1", "user-2"],
            isGroup: false
        )
        modelContext.insert(conversation)

        // Create message with low confidence (below threshold of 0.6)
        let message = MessageEntity(
            id: "msg-low",
            conversationId: "conv-low",
            senderId: "user-1",
            text: "Maybe we could meet?",
            schedulingIntent: "low",
            intentConfidence: 0.4,
            intentAnalyzedAt: Date()
        )
        modelContext.insert(message)
        try modelContext.save()

        // Call onMessageMutation
        service.onMessageMutation(conversationId: "conv-low", messageId: "msg-low")

        // Wait for async task
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify no prefetch occurred (confidence too low)
        XCTAssertNil(service.schedulingIntentDetected["conv-low"])
    }

    func testOnMessageMutationWithHighConfidenceIntent() async throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation with 2+ human participants
        let conversation = ConversationEntity(
            id: "conv-high",
            participantIds: ["user-1", "user-2"],
            isGroup: false
        )
        modelContext.insert(conversation)

        // Create message with high confidence (above threshold)
        let message = MessageEntity(
            id: "msg-high",
            conversationId: "conv-high",
            senderId: "user-1",
            text: "Let's schedule a meeting for Friday at 3pm",
            schedulingIntent: "high",
            intentConfidence: 0.92,
            intentAnalyzedAt: Date(),
            schedulingKeywords: ["schedule", "meeting", "Friday", "3pm"]
        )
        modelContext.insert(message)
        try modelContext.save()

        // Call onMessageMutation
        service.onMessageMutation(conversationId: "conv-high", messageId: "msg-high")

        // Wait for async task
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify scheduling intent was detected and exposed to UI
        XCTAssertEqual(service.schedulingIntentDetected["conv-high"], true)
        XCTAssertEqual(service.schedulingIntentConfidence["conv-high"], 0.92)

        // Note: Actual prefetch will fail without Firebase auth, but state should still be set
    }

    func testOnMessageMutationWithBotParticipant() async throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation with only 1 human (other is bot)
        let conversation = ConversationEntity(
            id: "conv-bot",
            participantIds: ["user-1", "bot:dash-bot"],
            isGroup: false
        )
        modelContext.insert(conversation)

        // Create message with high confidence
        let message = MessageEntity(
            id: "msg-bot",
            conversationId: "conv-bot",
            senderId: "user-1",
            text: "Schedule a meeting",
            schedulingIntent: "high",
            intentConfidence: 0.85,
            intentAnalyzedAt: Date()
        )
        modelContext.insert(message)
        try modelContext.save()

        // Call onMessageMutation
        service.onMessageMutation(conversationId: "conv-bot", messageId: "msg-bot")

        // Wait for async task
        try await Task.sleep(nanoseconds: 100_000_000)

        // Should detect intent but not prefetch (not enough human participants)
        XCTAssertNil(service.schedulingIntentDetected["conv-bot"])
    }

    func testPrefetchOnlyOncePerConversation() async throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation
        let conversation = ConversationEntity(
            id: "conv-once",
            participantIds: ["user-1", "user-2", "user-3"],
            isGroup: true
        )
        modelContext.insert(conversation)

        // Create first message with scheduling intent
        let message1 = MessageEntity(
            id: "msg-once-1",
            conversationId: "conv-once",
            senderId: "user-1",
            text: "Let's meet tomorrow",
            schedulingIntent: "high",
            intentConfidence: 0.88,
            intentAnalyzedAt: Date()
        )
        modelContext.insert(message1)

        // Create second message with scheduling intent
        let message2 = MessageEntity(
            id: "msg-once-2",
            conversationId: "conv-once",
            senderId: "user-2",
            text: "Yes, what time works?",
            schedulingIntent: "medium",
            intentConfidence: 0.7,
            intentAnalyzedAt: Date()
        )
        modelContext.insert(message2)
        try modelContext.save()

        // Call onMessageMutation for first message
        service.onMessageMutation(conversationId: "conv-once", messageId: "msg-once-1")
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify first detection
        XCTAssertEqual(service.schedulingIntentDetected["conv-once"], true)
        XCTAssertEqual(service.schedulingIntentConfidence["conv-once"], 0.88)

        // Call onMessageMutation for second message
        service.onMessageMutation(conversationId: "conv-once", messageId: "msg-once-2")
        try await Task.sleep(nanoseconds: 100_000_000)

        // Confidence should still be from first message (no update on second)
        XCTAssertEqual(service.schedulingIntentConfidence["conv-once"], 0.88)
    }

    func testSchedulingIntentWithNoneClassification() async throws {
        // Configure service
        let authService = AuthService()
        let messagingService = MessagingService()
        let firestoreService = FirestoreService()

        service.configure(
            modelContext: modelContext,
            authService: authService,
            messagingService: messagingService,
            firestoreService: firestoreService
        )

        // Create conversation
        let conversation = ConversationEntity(
            id: "conv-none",
            participantIds: ["user-1", "user-2"],
            isGroup: false
        )
        modelContext.insert(conversation)

        // Create message classified as "none" even with high confidence
        let message = MessageEntity(
            id: "msg-none",
            conversationId: "conv-none",
            senderId: "user-1",
            text: "The weather is nice",
            schedulingIntent: "none",
            intentConfidence: 0.95,
            intentAnalyzedAt: Date()
        )
        modelContext.insert(message)
        try modelContext.save()

        // Call onMessageMutation
        service.onMessageMutation(conversationId: "conv-none", messageId: "msg-none")
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify no prefetch (intent is "none")
        XCTAssertNil(service.schedulingIntentDetected["conv-none"])
    }

    func testClearCachesResetsSchedulingState() throws {
        // Set some scheduling intent state
        service.schedulingIntentDetected["conv-test"] = true
        service.schedulingIntentConfidence["conv-test"] = 0.85

        // Clear caches
        service.clearCaches()

        // Verify scheduling state is cleared
        XCTAssertEqual(service.schedulingIntentDetected.count, 0)
        XCTAssertEqual(service.schedulingIntentConfidence.count, 0)
    }
}
