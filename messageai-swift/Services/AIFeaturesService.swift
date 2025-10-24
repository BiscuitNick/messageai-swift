//
//  AIFeaturesService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-23.
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import SwiftData

/// Centralized service for orchestrating AI workflows via Firebase functions
@MainActor
@Observable
final class AIFeaturesService {

    // MARK: - Public State

    /// Indicates if an AI operation is currently in progress
    var isProcessing = false

    /// Latest error message from AI operations
    var errorMessage: String?

    /// Per-conversation summary loading state
    var summaryLoadingStates: [String: Bool] = [:]

    /// Per-conversation summary error messages
    var summaryErrors: [String: String] = [:]

    /// Per-conversation action items loading state
    var actionItemsLoadingStates: [String: Bool] = [:]

    /// Per-conversation action items error messages
    var actionItemsErrors: [String: String] = [:]

    /// Global search loading state
    var searchLoadingState = false

    /// Global search error message
    var searchError: String?

    /// Per-conversation meeting suggestions loading state
    var meetingSuggestionsLoadingStates: [String: Bool] = [:]

    /// Per-conversation meeting suggestions error messages
    var meetingSuggestionsErrors: [String: String] = [:]

    // MARK: - Private Dependencies

    @ObservationIgnored
    private let firestore = Firestore.firestore()

    @ObservationIgnored
    private let functions = Functions.functions(region: "us-central1")

    @ObservationIgnored
    private var modelContext: ModelContext?

    @ObservationIgnored
    private var authService: AuthService?

    @ObservationIgnored
    private var messagingService: MessagingService?

    @ObservationIgnored
    private var firestoreService: FirestoreService?

    // MARK: - Caches

    /// Cached summary entry with expiration
    private struct CachedSummary {
        let response: ThreadSummaryResponse
        let cachedAt: Date

        var isExpired: Bool {
            // Cache expires after 1 hour
            Date().timeIntervalSince(cachedAt) > 3600
        }
    }

    /// Cached action items entry with expiration
    private struct CachedActionItems {
        let response: ActionItemsResponse
        let cachedAt: Date

        var isExpired: Bool {
            // Cache expires after 1 hour
            Date().timeIntervalSince(cachedAt) > 3600
        }
    }

    /// Cached search results entry with expiration
    private struct CachedSearchResults {
        let query: String
        let results: [SearchResultEntity]
        let cachedAt: Date

        var isExpired: Bool {
            // Cache expires after 1 hour
            Date().timeIntervalSince(cachedAt) > 3600
        }
    }

    /// Cached meeting suggestions entry with expiration
    private struct CachedMeetingSuggestions {
        let response: MeetingSuggestionsResponse
        let cachedAt: Date

        var isExpired: Bool {
            // Use expiry from response
            Date() > response.expiresAt
        }
    }

    @ObservationIgnored
    private var summaryCache: [String: CachedSummary] = [:]

    @ObservationIgnored
    private var searchCache: [String: CachedSearchResults] = [:]

    @ObservationIgnored
    private var actionItemsCache: [String: CachedActionItems] = [:]

    @ObservationIgnored
    private var meetingSuggestionsCache: [String: CachedMeetingSuggestions] = [:]

    // MARK: - Initialization

    init() {
        // Firebase Functions already initialized via FirebaseApp.configure()
    }

    // MARK: - Configuration

    /// Configure the service with required dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local persistence
    ///   - authService: Authentication service for user lifecycle
    ///   - messagingService: Messaging service for message mutation observation
    ///   - firestoreService: Firestore service for database operations
    func configure(
        modelContext: ModelContext,
        authService: AuthService,
        messagingService: MessagingService,
        firestoreService: FirestoreService
    ) {
        self.modelContext = modelContext
        self.authService = authService
        self.messagingService = messagingService
        self.firestoreService = firestoreService
    }

    // MARK: - Generic Callable Helper

    /// Generic helper to call Firebase Cloud Functions and decode response
    /// - Parameters:
    ///   - name: Function name to invoke
    ///   - payload: Request payload as dictionary
    /// - Returns: Decoded response of type T
    /// - Throws: Function call or decoding errors
    func call<T: Decodable>(_ name: String, payload: [String: Any] = [:]) async throws -> T {
        isProcessing = true
        errorMessage = nil

        defer {
            isProcessing = false
        }

        do {
            // Force token refresh to ensure Firebase Auth has a valid token
            // This token is automatically attached to the Cloud Function request
            if let currentUser = Auth.auth().currentUser {
                do {
                    _ = try await currentUser.getIDToken(forcingRefresh: true)
                } catch {
                    print("[AIFeaturesService] Token refresh failed: \(error.localizedDescription)")
                    // Continue anyway - might still work with cached token
                }
            }

            let result = try await functions.httpsCallable(name).call(payload)

            guard let data = result.data as? [String: Any] else {
                throw AIFeaturesError.invalidResponse
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)

            // Configure decoder to handle ISO8601 date strings from backend
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: jsonData)

            return decoded
        } catch {
            let detailedError: String
            if let decodingError = error as? DecodingError {
                detailedError = formatDecodingError(decodingError)
                print("[AIFeaturesService] Decoding error for '\(name)': \(detailedError)")
            } else {
                detailedError = error.localizedDescription
                print("[AIFeaturesService] Error calling '\(name)': \(detailedError)")
            }
            errorMessage = detailedError
            throw error
        }
    }

    /// Format a DecodingError into a human-readable message
    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }

    // MARK: - Cache Management

    /// Clear all in-memory caches
    func clearCaches() {
        summaryCache.removeAll()
        searchCache.removeAll()
        actionItemsCache.removeAll()
        meetingSuggestionsCache.removeAll()
    }

    /// Reset service state (called on sign-out)
    func reset() {
        clearCaches()
        isProcessing = false
        errorMessage = nil
        searchLoadingState = false
        searchError = nil

        // Clear search results from SwiftData
        clearSearchDataFromSwiftData()
    }

    /// Clear search-related data from SwiftData (search results and recent queries)
    private func clearSearchDataFromSwiftData() {
        guard let modelContext = modelContext else { return }

        do {
            // Delete all SearchResultEntity instances
            let searchDescriptor = FetchDescriptor<SearchResultEntity>()
            let searchResults = try modelContext.fetch(searchDescriptor)
            for result in searchResults {
                modelContext.delete(result)
            }

            // Delete all RecentQueryEntity instances
            let queryDescriptor = FetchDescriptor<RecentQueryEntity>()
            let recentQueries = try modelContext.fetch(queryDescriptor)
            for query in recentQueries {
                modelContext.delete(query)
            }

            try modelContext.save()

            #if DEBUG
            print("[AIFeaturesService] Cleared \(searchResults.count) search results and \(recentQueries.count) recent queries from SwiftData")
            #endif
        } catch {
            print("[AIFeaturesService] Error clearing search data: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle Hooks

    /// Called when user signs in
    func onSignIn() {
        // Warm caches or perform initial setup if needed
    }

    /// Called when user signs out
    func onSignOut() {
        reset()
    }

    // MARK: - Message Observer Hooks

    /// Called when a message is created or updated in a conversation
    /// - Parameters:
    ///   - conversationId: The ID of the conversation
    ///   - messageId: The ID of the message
    func onMessageMutation(conversationId: String, messageId: String) {
        // This will be used by future AI features to trigger analysis
        // For now, we just log the event for debugging
        #if DEBUG
        print("[AIFeaturesService] Message mutation: conversation=\(conversationId), message=\(messageId)")
        #endif

        // Future implementations will trigger AI analysis here:
        // - Check for action items
        // - Detect scheduling intent
        // - Update priority scores
        // - Track decisions
    }

    // MARK: - Thread Summary Persistence

    /// Save a thread summary to local SwiftData storage
    /// - Parameters:
    ///   - conversationId: The conversation being summarized
    ///   - summary: The summary text
    ///   - keyPoints: Array of key points from the conversation
    ///   - generatedAt: When the summary was generated
    ///   - messageCount: Number of messages included in the summary
    /// - Throws: SwiftData persistence errors
    func saveThreadSummary(
        conversationId: String,
        summary: String,
        keyPoints: [String],
        generatedAt: Date,
        messageCount: Int
    ) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        // Check if a summary already exists for this conversation
        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing summary
            existing.summary = summary
            existing.keyPoints = keyPoints
            existing.generatedAt = generatedAt
            existing.messageCount = messageCount
            existing.updatedAt = Date()
        } else {
            // Create new summary
            let entity = ThreadSummaryEntity(
                conversationId: conversationId,
                summary: summary,
                keyPoints: keyPoints,
                generatedAt: generatedAt,
                messageCount: messageCount
            )
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    /// Fetch the most recent thread summary for a conversation
    /// - Parameter conversationId: The conversation to fetch summary for
    /// - Returns: ThreadSummaryEntity if one exists, nil otherwise
    func fetchThreadSummary(for conversationId: String) -> ThreadSummaryEntity? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Delete a thread summary from local storage
    /// - Parameter conversationId: The conversation whose summary should be deleted
    /// - Throws: SwiftData persistence errors
    func deleteThreadSummary(for conversationId: String) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Thread Summarization API

    /// Generate a summary for a conversation by calling the Firebase Cloud Function
    /// - Parameters:
    ///   - conversationId: The conversation to summarize
    ///   - messageLimit: Maximum number of messages to include (default: 50)
    ///   - saveLocally: Whether to save the summary to local SwiftData storage (default: true)
    ///   - forceRefresh: Force a new summary even if cache is valid (default: false)
    /// - Returns: ThreadSummaryResponse with the generated summary
    /// - Throws: AIFeaturesError or network errors
    func summarizeThreadTask(
        conversationId: String,
        messageLimit: Int = 50,
        saveLocally: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> ThreadSummaryResponse {
        // Verify user is authenticated
        guard authService?.currentUser != nil else {
            summaryErrors[conversationId] = AIFeaturesError.unauthorized.errorDescription
            throw AIFeaturesError.unauthorized
        }

        // Set loading state
        summaryLoadingStates[conversationId] = true
        summaryErrors[conversationId] = nil

        defer {
            summaryLoadingStates[conversationId] = false
        }

        // Check cache first unless force refresh is requested
        if !forceRefresh,
           let cached = summaryCache[conversationId],
           !cached.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Returning cached summary for conversation \(conversationId)")
            #endif
            return cached.response
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localSummary = fetchThreadSummary(for: conversationId) {
            // Check if local summary is recent enough (within 1 hour)
            let age = Date().timeIntervalSince(localSummary.generatedAt)
            if age < 3600 {
                #if DEBUG
                print("[AIFeaturesService] Returning local summary for conversation \(conversationId)")
                #endif
                let response = ThreadSummaryResponse(
                    summary: localSummary.summary,
                    keyPoints: localSummary.keyPoints,
                    conversationId: localSummary.conversationId,
                    timestamp: localSummary.generatedAt,
                    messageCount: localSummary.messageCount
                )
                // Update memory cache
                summaryCache[conversationId] = CachedSummary(response: response, cachedAt: Date())
                return response
            }
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "messageLimit": messageLimit,
            ]

            // Call the Firebase Cloud Function
            let response: ThreadSummaryResponse = try await call("summarizeThreadTask", payload: payload)

            // Update memory cache
            summaryCache[conversationId] = CachedSummary(response: response, cachedAt: Date())

            // Optionally save to local storage
            if saveLocally {
                do {
                    try saveThreadSummary(
                        conversationId: response.conversationId,
                        summary: response.summary,
                        keyPoints: response.keyPoints,
                        generatedAt: response.timestamp,
                        messageCount: response.messageCount
                    )
                } catch {
                    // Log error but don't fail the entire operation
                    #if DEBUG
                    print("[AIFeaturesService] Failed to save summary locally: \(error)")
                    #endif
                }
            }

            return response
        } catch {
            summaryErrors[conversationId] = error.localizedDescription
            throw error
        }
    }

    // MARK: - Action Item Extraction API

    /// Extract action items from a conversation by calling the Firebase Cloud Function
    /// - Parameters:
    ///   - conversationId: The conversation to extract action items from
    ///   - windowDays: Number of days of message history to analyze (default: 7)
    ///   - forceRefresh: Force a new extraction even if cache is valid (default: false)
    /// - Returns: ActionItemsResponse with the extracted action items
    /// - Throws: AIFeaturesError or network errors
    func extractActionItems(
        conversationId: String,
        windowDays: Int = 7,
        forceRefresh: Bool = false
    ) async throws -> ActionItemsResponse {
        // Verify user is authenticated
        guard authService?.currentUser != nil else {
            actionItemsErrors[conversationId] = AIFeaturesError.unauthorized.errorDescription
            throw AIFeaturesError.unauthorized
        }

        // Set loading state
        actionItemsLoadingStates[conversationId] = true
        actionItemsErrors[conversationId] = nil

        defer {
            actionItemsLoadingStates[conversationId] = false
        }

        // Check cache first unless force refresh is requested
        if !forceRefresh,
           let cached = actionItemsCache[conversationId],
           !cached.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Returning cached action items for conversation \(conversationId)")
            #endif
            return cached.response
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "windowDays": windowDays,
            ]

            // Call the Firebase Cloud Function
            let response: ActionItemsResponse = try await call("extractActionItems", payload: payload)

            // Update memory cache
            actionItemsCache[conversationId] = CachedActionItems(response: response, cachedAt: Date())

            // Note: Firestore listener will automatically sync the action items to SwiftData
            // The Cloud Function writes to Firestore, which triggers the listener in FirestoreService

            return response
        } catch {
            actionItemsErrors[conversationId] = error.localizedDescription
            throw error
        }
    }

    // MARK: - Decision Tracking API

    /// Track decisions in a conversation by calling the Firebase Cloud Function
    /// - Parameters:
    ///   - conversationId: The conversation to analyze for decisions
    ///   - windowDays: Number of days of message history to analyze (default: 30)
    /// - Returns: TrackedDecisionsResponse with the extracted decisions
    /// - Throws: AIFeaturesError or network errors
    func recordDecisions(
        conversationId: String,
        windowDays: Int = 30
    ) async throws -> TrackedDecisionsResponse {
        // Verify user is authenticated
        guard authService?.currentUser != nil else {
            throw AIFeaturesError.unauthorized
        }

        isProcessing = true
        errorMessage = nil

        defer {
            isProcessing = false
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "windowDays": windowDays,
            ]

            // Call the Firebase Cloud Function
            let response: TrackedDecisionsResponse = try await call("recordDecisions", payload: payload)

            // Note: Firestore listener will automatically sync the decisions to SwiftData
            // The Cloud Function writes to Firestore, which triggers the listener in FirestoreService

            return response
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Fetch decisions for a conversation from local SwiftData storage
    /// - Parameter conversationId: The conversation to fetch decisions for
    /// - Returns: Array of DecisionEntity instances sorted by decidedAt (newest first)
    func fetchDecisions(for conversationId: String) -> [DecisionEntity] {
        guard let modelContext = modelContext else { return [] }

        let descriptor = FetchDescriptor<DecisionEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.decidedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch all decisions across all conversations from local SwiftData storage
    /// - Returns: Array of DecisionEntity instances sorted by decidedAt (newest first)
    func fetchAllDecisions() -> [DecisionEntity] {
        guard let modelContext = modelContext else { return [] }

        let descriptor = FetchDescriptor<DecisionEntity>(
            sortBy: [SortDescriptor(\.decidedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Update a decision's follow-up status in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to update
    ///   - followUpStatus: New follow-up status
    /// - Throws: Firestore errors
    func updateDecisionStatus(
        conversationId: String,
        decisionId: String,
        followUpStatus: DecisionFollowUpStatus
    ) async throws {
        guard let firestoreService = firestoreService else {
            throw AIFeaturesError.notConfigured
        }

        try await firestoreService.updateDecisionStatus(
            conversationId: conversationId,
            decisionId: decisionId,
            followUpStatus: followUpStatus
        )
    }

    /// Delete a decision from Firestore and local storage
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to delete
    /// - Throws: Firestore errors
    func deleteDecision(conversationId: String, decisionId: String) async throws {
        guard let firestoreService = firestoreService else {
            throw AIFeaturesError.notConfigured
        }

        try await firestoreService.deleteDecision(
            conversationId: conversationId,
            decisionId: decisionId
        )
    }

    // MARK: - Semantic Smart Search

    /// Perform semantic search across user's conversations
    /// - Parameters:
    ///   - query: Search query text
    ///   - maxResults: Maximum number of results to return (default: 20)
    ///   - forceRefresh: Force a new search even if cache is valid (default: false)
    /// - Returns: Array of SearchResultEntity instances
    /// - Throws: AIFeaturesError or network errors
    func smartSearch(
        query: String,
        maxResults: Int = 20,
        forceRefresh: Bool = false
    ) async throws -> [SearchResultEntity] {
        // Verify user is authenticated
        guard authService?.currentUser != nil else {
            searchError = AIFeaturesError.unauthorized.errorDescription
            throw AIFeaturesError.unauthorized
        }

        // Validate query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw AIFeaturesError.invalidResponse
        }

        // Set loading state
        searchLoadingState = true
        searchError = nil

        defer {
            searchLoadingState = false
        }

        // Check cache first unless force refresh is requested
        if !forceRefresh,
           let cached = searchCache[trimmedQuery],
           !cached.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Returning cached search results for query: \(trimmedQuery)")
            #endif
            return cached.results
        }

        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "query": trimmedQuery,
                "maxResults": maxResults,
            ]

            // Define response structure matching Firebase function output
            struct SmartSearchFirebaseResponse: Codable {
                let groupedResults: [GroupedResult]
                let query: String
                let totalHits: Int

                struct GroupedResult: Codable {
                    let conversationId: String
                    let hits: [Hit]
                }

                struct Hit: Codable {
                    let id: String
                    let conversationId: String
                    let messageId: String
                    let snippet: String
                    let rank: Int
                    let timestamp: String
                }

                enum CodingKeys: String, CodingKey {
                    case groupedResults = "grouped_results"
                    case query
                    case totalHits = "total_hits"
                }
            }

            // Call the Firebase Cloud Function
            let response: SmartSearchFirebaseResponse = try await call("smartSearch", payload: payload)

            // Transform to SearchResultEntity instances
            var searchResults: [SearchResultEntity] = []

            for group in response.groupedResults {
                for hit in group.hits {
                    // Parse timestamp
                    let formatter = ISO8601DateFormatter()
                    let timestamp = formatter.date(from: hit.timestamp) ?? Date()

                    let entity = SearchResultEntity(
                        query: trimmedQuery,
                        conversationId: hit.conversationId,
                        messageId: hit.messageId,
                        snippet: hit.snippet,
                        rank: hit.rank,
                        timestamp: timestamp
                    )

                    searchResults.append(entity)
                    modelContext.insert(entity)
                }
            }

            // Save to SwiftData
            try modelContext.save()

            // Save recent query
            let recentQuery = RecentQueryEntity(
                query: trimmedQuery,
                searchedAt: Date(),
                resultCount: searchResults.count
            )
            modelContext.insert(recentQuery)
            try modelContext.save()

            // Update memory cache
            searchCache[trimmedQuery] = CachedSearchResults(
                query: trimmedQuery,
                results: searchResults,
                cachedAt: Date()
            )

            #if DEBUG
            print("[AIFeaturesService] Smart search completed: \(searchResults.count) results for query '\(trimmedQuery)'")
            #endif

            return searchResults
        } catch {
            searchError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Meeting Suggestions API

    /// Fetch meeting time suggestions for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation to suggest meeting times for
    ///   - participantIds: Array of participant IDs to consider for availability
    ///   - durationMinutes: Duration of the meeting in minutes
    ///   - preferredDays: Number of days to look ahead for suggestions (default: 14)
    ///   - forceRefresh: Force a new suggestion even if cache is valid (default: false)
    /// - Returns: MeetingSuggestionsResponse with the generated suggestions
    /// - Throws: AIFeaturesError or network errors
    func suggestMeetingTimes(
        conversationId: String,
        participantIds: [String],
        durationMinutes: Int,
        preferredDays: Int = 14,
        forceRefresh: Bool = false
    ) async throws -> MeetingSuggestionsResponse {
        // Verify user is authenticated
        guard authService?.currentUser != nil else {
            meetingSuggestionsErrors[conversationId] = AIFeaturesError.unauthorized.errorDescription
            throw AIFeaturesError.unauthorized
        }

        // Set loading state
        meetingSuggestionsLoadingStates[conversationId] = true
        meetingSuggestionsErrors[conversationId] = nil

        defer {
            meetingSuggestionsLoadingStates[conversationId] = false
        }

        // Check cache first unless force refresh is requested
        if !forceRefresh,
           let cached = meetingSuggestionsCache[conversationId],
           !cached.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Returning cached meeting suggestions for conversation \(conversationId)")
            #endif
            return cached.response
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localSuggestions = fetchMeetingSuggestions(for: conversationId) {
            if localSuggestions.isValid {
                #if DEBUG
                print("[AIFeaturesService] Returning local meeting suggestions for conversation \(conversationId)")
                #endif
                let response = MeetingSuggestionsResponse(
                    suggestions: localSuggestions.suggestions.map { data in
                        MeetingTimeSuggestion(
                            startTime: data.startTime,
                            endTime: data.endTime,
                            score: data.score,
                            justification: data.justification,
                            dayOfWeek: data.dayOfWeek,
                            timeOfDay: TimeOfDay(rawValue: data.timeOfDay) ?? .afternoon
                        )
                    },
                    conversationId: localSuggestions.conversationId,
                    durationMinutes: localSuggestions.durationMinutes,
                    participantCount: localSuggestions.participantCount,
                    generatedAt: localSuggestions.generatedAt,
                    expiresAt: localSuggestions.expiresAt
                )
                // Update memory cache
                meetingSuggestionsCache[conversationId] = CachedMeetingSuggestions(
                    response: response,
                    cachedAt: Date()
                )
                return response
            } else {
                // Delete expired suggestions
                try? deleteMeetingSuggestions(for: conversationId)
            }
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "participantIds": participantIds,
                "durationMinutes": durationMinutes,
                "preferredDays": preferredDays,
            ]

            // Call the Firebase Cloud Function
            let response: MeetingSuggestionsResponse = try await call("suggestMeetingTimes", payload: payload)

            // Update memory cache
            meetingSuggestionsCache[conversationId] = CachedMeetingSuggestions(
                response: response,
                cachedAt: Date()
            )

            // Save to local storage
            do {
                try saveMeetingSuggestions(response: response)
            } catch {
                // Log error but don't fail the entire operation
                #if DEBUG
                print("[AIFeaturesService] Failed to save meeting suggestions locally: \(error)")
                #endif
            }

            return response
        } catch {
            meetingSuggestionsErrors[conversationId] = error.localizedDescription
            throw error
        }
    }

    /// Save meeting suggestions to local SwiftData storage
    /// - Parameter response: The meeting suggestions response to save
    /// - Throws: SwiftData persistence errors
    private func saveMeetingSuggestions(response: MeetingSuggestionsResponse) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        // Check if suggestions already exist for this conversation
        let descriptor = FetchDescriptor<MeetingSuggestionEntity>(
            predicate: #Predicate { $0.conversationId == response.conversationId }
        )

        // Convert suggestions to data format
        let suggestionsData = response.suggestions.map { suggestion in
            MeetingTimeSuggestionData(
                startTime: suggestion.startTime,
                endTime: suggestion.endTime,
                score: suggestion.score,
                justification: suggestion.justification,
                dayOfWeek: suggestion.dayOfWeek,
                timeOfDay: suggestion.timeOfDay.rawValue
            )
        }

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing suggestions
            existing.suggestions = suggestionsData
            existing.durationMinutes = response.durationMinutes
            existing.participantCount = response.participantCount
            existing.generatedAt = response.generatedAt
            existing.expiresAt = response.expiresAt
            existing.updatedAt = Date()
        } else {
            // Create new suggestions entity
            let entity = MeetingSuggestionEntity(
                conversationId: response.conversationId,
                suggestions: suggestionsData,
                durationMinutes: response.durationMinutes,
                participantCount: response.participantCount,
                generatedAt: response.generatedAt,
                expiresAt: response.expiresAt
            )
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    /// Fetch meeting suggestions for a conversation from local SwiftData storage
    /// - Parameter conversationId: The conversation to fetch suggestions for
    /// - Returns: MeetingSuggestionEntity if one exists and is valid, nil otherwise
    func fetchMeetingSuggestions(for conversationId: String) -> MeetingSuggestionEntity? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<MeetingSuggestionEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Delete meeting suggestions for a conversation from local storage
    /// - Parameter conversationId: The conversation whose suggestions should be deleted
    /// - Throws: SwiftData persistence errors
    func deleteMeetingSuggestions(for conversationId: String) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<MeetingSuggestionEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    /// Clear all expired meeting suggestions from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredMeetingSuggestions() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<MeetingSuggestionEntity>()
        let allSuggestions = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for suggestion in allSuggestions where suggestion.isExpired {
            modelContext.delete(suggestion)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired meeting suggestions")
            #endif
        }
    }

    /// Track meeting suggestion interaction analytics
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - action: The action taken (e.g., "copy", "share", "dismiss", "accept")
    ///   - suggestionIndex: The index of the suggestion interacted with (0-based)
    ///   - suggestionScore: The score of the suggestion
    func trackMeetingSuggestionInteraction(
        conversationId: String,
        action: String,
        suggestionIndex: Int,
        suggestionScore: Double
    ) async {
        guard let firestoreService = firestoreService else {
            #if DEBUG
            print("[AIFeaturesService] Cannot track analytics - FirestoreService not configured")
            #endif
            return
        }

        do {
            // Track interaction in analytics/meetingSuggestions/interactions subcollection
            let analyticsRef = firestoreService.db
                .collection("analytics")
                .document("meetingSuggestions")
                .collection("interactions")

            try await analyticsRef.addDocument(data: [
                "conversationId": conversationId,
                "action": action,
                "suggestionIndex": suggestionIndex,
                "suggestionScore": suggestionScore,
                "timestamp": Timestamp(date: Date())
            ])

            // Also increment counter for this action type
            let summaryRef = firestoreService.db
                .collection("analytics")
                .document("meetingSuggestions")

            try await summaryRef.updateData([
                "interactions.\(action)": FieldValue.increment(Int64(1)),
                "lastInteractionAt": FieldValue.serverTimestamp()
            ])

            #if DEBUG
            print("[AIFeaturesService] Tracked meeting suggestion interaction: \(action) for conversation \(conversationId)")
            #endif
        } catch {
            #if DEBUG
            print("[AIFeaturesService] Failed to track analytics (non-fatal): \(error.localizedDescription)")
            #endif
            // Analytics failures should not block the user experience
        }
    }

    // MARK: - Background Task Helpers

    /// Execute AI analysis in the background with MainActor updates
    /// - Parameters:
    ///   - conversationId: The conversation to analyze
    ///   - operation: The AI operation to perform
    ///   - onComplete: Completion handler called on MainActor
    private func performBackgroundAIAnalysis<T>(
        conversationId: String,
        operation: @escaping () async throws -> T,
        onComplete: @escaping @MainActor (Result<T, Error>) -> Void
    ) {
        Task.detached { [weak self] in
            do {
                let result = try await operation()
                await MainActor.run {
                    guard self != nil else { return }
                    onComplete(.success(result))
                }
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    self.errorMessage = error.localizedDescription
                    onComplete(.failure(error))
                }
            }
        }
    }

    /// Example method showing background task pattern for future AI features
    func analyzeConversationInBackground(conversationId: String) {
        performBackgroundAIAnalysis(conversationId: conversationId) {
            // This is where the actual AI callable would be invoked
            // For now, return a placeholder
            return "Analysis placeholder"
        } onComplete: { [weak self] result in
            // MainActor-isolated completion handler
            guard let self = self else { return }
            switch result {
            case .success(let analysis):
                #if DEBUG
                print("[AIFeaturesService] Background analysis complete: \(analysis)")
                #endif
                // Future: Update cache with results
                // Future: Trigger UI updates via @Observable properties
            case .failure(let error):
                #if DEBUG
                print("[AIFeaturesService] Background analysis failed: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Error Types

enum AIFeaturesError: LocalizedError {
    case invalidResponse
    case notConfigured
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .notConfigured:
            return "AIFeaturesService not properly configured"
        case .unauthorized:
            return "User not authorized for AI features"
        }
    }
}
