//
//  AIFeaturesService.swift
//  messageai-swift
//
//  Created by Claude Code on 10/23/25.
//

import Foundation
import Observation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

@MainActor
@Observable
final class AIFeaturesService: MessageObserver {
    // Firebase references
    private let db: Firestore
    private let functions: Functions

    // Cache storage
    @ObservationIgnored private var summaryCache: [String: Any] = [:]
    @ObservationIgnored private var searchResultsCache: [String: Any] = [:]

    // Configuration state
    @ObservationIgnored private var isConfigured: Bool = false
    @ObservationIgnored private weak var messagingService: MessagingService?

    // Background task management
    @ObservationIgnored private var backgroundTasks: [String: Task<Void, Never>] = [:]

    // Persistence
    @ObservationIgnored private var modelContext: ModelContext?

    init() {
        // Initialize Firestore with settings
        let firestore = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        firestore.settings = settings
        self.db = firestore

        // Initialize Functions for the same region as our deployed functions
        self.functions = Functions.functions(region: "us-central1")
    }

    // MARK: - Configuration

    func configure(messagingService: MessagingService? = nil, modelContext: ModelContext? = nil) {
        guard !isConfigured else { return }
        isConfigured = true

        // Store reference to messaging service
        self.messagingService = messagingService

        // Store model context for persistence
        self.modelContext = modelContext

        // Register as observer if messaging service is provided
        if let messagingService {
            messagingService.addObserver(self)
            debugLog("Registered as message observer")
        }

        debugLog("AIFeaturesService configured")
    }

    func reset() {
        // Unregister as observer
        if let messagingService {
            messagingService.removeObserver(self)
        }

        // Cancel all background tasks
        cancelAllBackgroundTasks()

        // Clear caches and state
        clearCaches()
        messagingService = nil
        isConfigured = false
        debugLog("AIFeaturesService reset")
    }

    // MARK: - MessageObserver Protocol

    func didAddMessage(messageId: String, conversationId: String, senderId: String, text: String) {
        debugLog("Message added: \(messageId) in conversation: \(conversationId)")

        // Example: Process message in background
        scheduleBackgroundTask(id: "analyze-\(messageId)") { [weak self] in
            guard let self else { return }
            // Future: Trigger AI analysis for new messages
            // - Detect action items
            // - Update conversation summary
            // - Generate proactive insights
            await self.debugLog("Background analysis complete for message: \(messageId)")
        }
    }

    func didUpdateMessage(messageId: String, conversationId: String) {
        debugLog("Message updated: \(messageId) in conversation: \(conversationId)")
        // Future: Handle message updates
        // - Re-analyze if content changed
        // - Invalidate related caches
    }

    func didDeleteMessage(messageId: String, conversationId: String) {
        debugLog("Message deleted: \(messageId) in conversation: \(conversationId)")
        // Future: Handle message deletions
        // - Invalidate caches for conversation
        // - Update summaries if needed
    }

    func didUpdateConversation(conversationId: String) {
        debugLog("Conversation updated: \(conversationId)")
        // Future: Handle conversation updates
        // - Invalidate summary cache
        // - Check for new participants
        invalidateSummaryCache(for: conversationId)
    }

    // MARK: - Generic Firebase Function Caller

    /// Generic method to call Firebase Functions and decode the response
    /// - Parameters:
    ///   - name: The name of the Firebase Function to call
    ///   - payload: The data to send to the function
    /// - Returns: Decoded response of type T
    func call<T: Decodable>(_ name: String, payload: [String: Any]) async throws -> T {
        debugLog("=== Firebase Function Call Start ===")
        debugLog("Function: \(name)")
        debugLog("Payload: \(payload)")
        debugLog("Functions instance: \(functions)")

        // Check authentication
        guard let currentUser = Auth.auth().currentUser else {
            debugLog("❌ Function call failed: User not authenticated")
            throw AIFeaturesError.notAuthenticated
        }

        debugLog("✅ User authenticated: \(currentUser.uid)")
        debugLog("User email: \(currentUser.email ?? "no email")")
        debugLog("User isAnonymous: \(currentUser.isAnonymous)")

        // Get ID token to verify auth state
        do {
            let token = try await currentUser.getIDToken()
            debugLog("✅ ID Token obtained (length: \(token.count))")
            debugLog("Token first 30 chars: \(String(token.prefix(30)))...")
        } catch {
            debugLog("❌ Failed to get ID token: \(error.localizedDescription)")
            throw AIFeaturesError.networkError("Failed to get authentication token: \(error.localizedDescription)")
        }

        debugLog("Preparing to call Firebase Function: \(name) in region us-central1")
        debugLog("Creating httpsCallable for function: \(name)")

        do {
            let callable = functions.httpsCallable(name)
            debugLog("Callable created: \(callable)")
            debugLog("Calling function with payload...")

            let result = try await callable.call(payload)
            debugLog("✅ Function returned successfully")

            guard let data = result.data as? [String: Any] else {
                debugLog("❌ Invalid response format: \(type(of: result.data))")
                throw AIFeaturesError.invalidResponse
            }

            debugLog("✅ Response data received, decoding...")
            let decoded = try decode(data) as T
            debugLog("✅ Decoding successful")
            debugLog("=== Firebase Function Call End ===")
            return decoded
        } catch let error as NSError {
            debugLog("❌ Firebase Function Error:")
            debugLog("  Domain: \(error.domain)")
            debugLog("  Code: \(error.code)")
            debugLog("  Description: \(error.localizedDescription)")
            debugLog("  UserInfo: \(error.userInfo)")

            // Check if it's a Functions error
            if error.domain == "com.firebase.functions" {
                if let code = FunctionsErrorCode(rawValue: error.code) {
                    debugLog("  Functions Error Code: \(code)")
                }
            }

            debugLog("=== Firebase Function Call Failed ===")
            throw error
        }
    }

    // MARK: - AI Feature Methods (Stubs)

    /// Generate a summary for a conversation
    /// Uses background task for network call and caches result
    func generateSummary(conversationId: String) async throws -> String {
        // Check cache first
        if let cached = summaryCache[conversationId] as? String {
            debugLog("Returning cached summary for conversation: \(conversationId)")
            return cached
        }

        let payload: [String: Any] = ["conversationId": conversationId]

        let response: SummaryResponse = try await call("generateSummary", payload: payload)

        // Update cache
        summaryCache[conversationId] = response.summary

        return response.summary
    }

    /// Summarize a conversation thread
    /// - Parameters:
    ///   - conversationId: Optional conversation ID. If provided, summarizes that conversation. If nil, finds and summarizes the newest conversation.
    ///   - saveToDB: Whether to save the summary to SwiftData (default: false)
    /// - Returns: ThreadSummaryResponse with summary and metadata
    func summarizeThread(conversationId: String? = nil, saveToDB: Bool = false) async throws -> ThreadSummaryResponse {
        debugLog("=== Starting Thread Summarization ===")
        if let conversationId = conversationId {
            debugLog("Summarizing specific conversation: \(conversationId)")
        } else {
            debugLog("Finding and summarizing newest conversation")
        }

        do {
            debugLog("About to call Firebase function 'summarizeThreadTest'")

            // Build payload with optional conversationId
            var payload: [String: Any] = [:]
            if let conversationId = conversationId {
                payload["conversationId"] = conversationId
            }

            let result = try await functions.httpsCallable("summarizeThreadTest").call(payload)

            debugLog("✅ Function returned, processing response...")

            // Extract and decode the response
            guard let responseData = result.data as? [String: Any] else {
                debugLog("❌ Invalid response format")
                throw AIFeaturesError.invalidResponse
            }

            let response = try decode(responseData) as ThreadSummaryResponse
            debugLog("✅ Function call succeeded")

            // Update cache using the conversationId from the response
            summaryCache[response.conversationId] = response
            debugLog("Thread summary cached for conversation: \(response.conversationId)")
            debugLog("Thread summary generated successfully")

            // Save to SwiftData if requested and context is available
            if saveToDB, let modelContext {
                let entity = ThreadSummaryEntity(
                    conversationId: response.conversationId,
                    summary: response.summary,
                    messageCount: response.messageCount,
                    generatedAt: response.generatedAt,
                    isSaved: true
                )
                modelContext.insert(entity)
                try modelContext.save()
                debugLog("Thread summary saved to database")
            }

            return response
        } catch let error as NSError {
            debugLog("❌ Failed to summarize thread - NSError")
            debugLog("  Error domain: \(error.domain)")
            debugLog("  Error code: \(error.code)")
            debugLog("  Error description: \(error.localizedDescription)")
            debugLog("  Error userInfo: \(error.userInfo)")
            throw error
        } catch {
            debugLog("❌ Failed to summarize thread - Generic Error")
            debugLog("  Error type: \(type(of: error))")
            debugLog("  Error description: \(error.localizedDescription)")
            throw error
        }
    }

    /// Save a thread summary to the database
    /// - Parameter summary: The ThreadSummaryResponse to save
    func saveThreadSummary(_ summary: ThreadSummaryResponse) throws {
        guard let modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let entity = ThreadSummaryEntity(
            conversationId: summary.conversationId,
            summary: summary.summary,
            messageCount: summary.messageCount,
            generatedAt: summary.generatedAt,
            isSaved: true
        )
        modelContext.insert(entity)
        try modelContext.save()
        debugLog("Thread summary saved to database")
    }

    /// Fetch saved thread summaries for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of saved ThreadSummaryEntity objects
    func fetchSavedSummaries(for conversationId: String) throws -> [ThreadSummaryEntity] {
        guard let modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Extract action items from a conversation
    func extractActionItems(conversationId: String) async throws -> [ActionItem] {
        let payload: [String: Any] = ["conversationId": conversationId]
        let response: ActionItemsResponse = try await call("extractActionItems", payload: payload)
        return response.actionItems
    }

    /// Search messages using AI
    func searchMessages(query: String, conversationId: String? = nil) async throws -> [SearchResult] {
        var payload: [String: Any] = ["query": query]
        if let conversationId {
            payload["conversationId"] = conversationId
        }

        let response: SearchResponse = try await call("searchMessages", payload: payload)
        return response.results
    }

    /// Update message priority
    func updatePriority(messageId: String, priority: MessagePriority) async throws {
        let payload: [String: Any] = [
            "messageId": messageId,
            "priority": priority.rawValue
        ]

        let _: PriorityUpdateResponse = try await call("updatePriority", payload: payload)
        debugLog("Priority updated for message: \(messageId)")
    }

    /// Get decision suggestions for a conversation
    func getDecisionSuggestions(conversationId: String) async throws -> [Decision] {
        let payload: [String: Any] = ["conversationId": conversationId]
        let response: DecisionsResponse = try await call("getDecisions", payload: payload)
        return response.decisions
    }

    /// Get proactive insights
    func getProactiveInsights(userId: String) async throws -> [Insight] {
        let payload: [String: Any] = ["userId": userId]
        let response: InsightsResponse = try await call("getInsights", payload: payload)
        return response.insights
    }

    // MARK: - Cache Management

    private func clearCaches() {
        summaryCache.removeAll()
        searchResultsCache.removeAll()
        debugLog("Caches cleared")
    }

    func invalidateSummaryCache(for conversationId: String) {
        summaryCache.removeValue(forKey: conversationId)
        debugLog("Summary cache invalidated for conversation: \(conversationId)")
    }

    func invalidateThreadSummaryCache(for conversationId: String) {
        invalidateSummaryCache(for: conversationId)
    }

    // MARK: - Thread Summary Helper Methods

    func isSummaryLoading(for conversationId: String) -> Bool {
        return backgroundTasks["summary-\(conversationId)"] != nil
    }

    func getSummaryError(for conversationId: String) -> Error? {
        // Could be extended to track errors per conversation if needed
        return nil
    }

    func clearSummaryError(for conversationId: String) {
        // Placeholder for error clearing
        debugLog("Summary error cleared for conversation: \(conversationId)")
    }

    func getSavedThreadSummary(for conversationId: String) -> ThreadSummaryEntity? {
        guard let modelContext else { return nil }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId && $0.isSaved == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let summaries = try? modelContext.fetch(descriptor),
              let latest = summaries.first else {
            return nil
        }

        return latest
    }

    func deleteThreadSummary(for conversationId: String) throws {
        guard let modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        let summaries = try modelContext.fetch(descriptor)
        for summary in summaries {
            modelContext.delete(summary)
        }
        try modelContext.save()
        debugLog("Thread summaries deleted for conversation: \(conversationId)")
    }

    // MARK: - Background Task Management

    /// Schedule a background task using Task.detached
    /// Results are posted to MainActor for UI updates
    private func scheduleBackgroundTask(id: String, work: @escaping @Sendable () async -> Void) {
        // Cancel existing task with same ID if present
        if let existingTask = backgroundTasks[id] {
            existingTask.cancel()
        }

        let task = Task.detached { [weak self] in
            await work()

            // Clean up task reference on main actor
            _ = await MainActor.run { [weak self] in
                self?.backgroundTasks.removeValue(forKey: id)
            }
        }

        backgroundTasks[id] = task
    }

    /// Cancel a specific background task
    func cancelBackgroundTask(id: String) {
        backgroundTasks[id]?.cancel()
        backgroundTasks.removeValue(forKey: id)
    }

    /// Cancel all active background tasks
    private func cancelAllBackgroundTasks() {
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        debugLog("All background tasks cancelled")
    }

    // MARK: - Helper Methods

    private func decode<T: Decodable>(_ data: [String: Any]) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: jsonData)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AIFeaturesService]", message)
        #endif
    }
}

// MARK: - Error Types

enum AIFeaturesError: Error, LocalizedError, Equatable {
    case invalidResponse
    case notConfigured
    case notAuthenticated
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .notConfigured:
            return "AIFeaturesService not configured"
        case .notAuthenticated:
            return "You must be signed in to use AI features"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }

    static func == (lhs: AIFeaturesError, rhs: AIFeaturesError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse),
             (.notConfigured, .notConfigured),
             (.notAuthenticated, .notAuthenticated):
            return true
        case (.networkError(let lhsMessage), .networkError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
