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

    /// Per-conversation scheduling intent detection state
    var schedulingIntentDetected: [String: Bool] = [:]

    /// Per-conversation scheduling intent confidence scores
    var schedulingIntentConfidence: [String: Double] = [:]

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

    @ObservationIgnored
    private var networkMonitor: NetworkMonitor?

    // MARK: - Offline Queue

    /// Pending scheduling suggestion requests to retry when network returns
    private struct PendingSchedulingSuggestion: Hashable {
        let conversationId: String
        let messageId: String
        let timestamp: Date
    }

    @ObservationIgnored
    private var pendingSchedulingSuggestions: Set<PendingSchedulingSuggestion> = []

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

    /// Track conversations where we've already auto-prefetched meeting suggestions
    @ObservationIgnored
    private var prefetchedConversations: Set<String> = []

    /// Track last prefetch timestamp per conversation for debouncing
    @ObservationIgnored
    private var lastPrefetchTimestamps: [String: Date] = [:]

    /// Debounce interval in seconds (default: 5 minutes)
    private let debounceInterval: TimeInterval = 300

    // MARK: - Telemetry

    /// Telemetry event capturing AI call metrics
    private struct TelemetryEvent: Codable {
        let eventId: String
        let userId: String?
        let functionName: String
        let startTime: Date
        let endTime: Date
        let durationMs: Int
        let success: Bool
        let attemptCount: Int
        let errorType: String?
        let errorMessage: String?
        let cacheHit: Bool
        let timestamp: Date

        init(
            userId: String?,
            functionName: String,
            startTime: Date,
            endTime: Date,
            success: Bool,
            attemptCount: Int,
            errorType: String? = nil,
            errorMessage: String? = nil,
            cacheHit: Bool = false
        ) {
            self.eventId = UUID().uuidString
            self.userId = userId
            self.functionName = functionName
            self.startTime = startTime
            self.endTime = endTime
            self.durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
            self.success = success
            self.attemptCount = attemptCount
            self.errorType = errorType
            self.errorMessage = errorMessage
            self.cacheHit = cacheHit
            self.timestamp = Date()
        }

        func toDictionary() -> [String: Any] {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(self),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return dict
        }
    }

    /// Enable/disable telemetry logging (can be controlled by user settings or build config)
    private var telemetryEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "ai_telemetry_enabled")
        #endif
    }

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
    ///   - networkMonitor: Network monitor for connectivity awareness
    func configure(
        modelContext: ModelContext,
        authService: AuthService,
        messagingService: MessagingService,
        firestoreService: FirestoreService,
        networkMonitor: NetworkMonitor
    ) {
        self.modelContext = modelContext
        self.authService = authService
        self.messagingService = messagingService
        self.firestoreService = firestoreService
        self.networkMonitor = networkMonitor
    }

    // MARK: - Telemetry Logging

    /// Log telemetry event to Firestore analytics collection
    /// - Parameter event: The telemetry event to log
    private func logTelemetry(_ event: TelemetryEvent) {
        guard telemetryEnabled else { return }

        Task { [weak self] in
            guard let self = self,
                  let firestoreService = await self.firestoreService else {
                return
            }

            do {
                // Access firestore on MainActor
                let db = await MainActor.run { firestoreService.firestore }
                let collectionRef = db.collection("ai_telemetry")

                try await collectionRef.document(event.eventId).setData(event.toDictionary())

                #if DEBUG
                await MainActor.run {
                    print("[AIFeaturesService] Logged telemetry: \(event.functionName) - \(event.success ? "success" : "failure") in \(event.durationMs)ms (attempts: \(event.attemptCount))")
                }
                #endif
            } catch {
                #if DEBUG
                await MainActor.run {
                    print("[AIFeaturesService] Failed to log telemetry: \(error.localizedDescription)")
                }
                #endif
            }
        }
    }

    // MARK: - Retry Configuration

    /// Retry configuration constants
    private enum RetryConfig {
        static let maxAttempts = 3
        static let baseDelayNanoseconds: UInt64 = 500_000_000 // 0.5 seconds
        static let maxDelayNanoseconds: UInt64 = 8_000_000_000 // 8 seconds
    }

    // MARK: - Generic Callable Helper

    /// Generic helper to call Firebase Cloud Functions and decode response with retry logic
    /// - Parameters:
    ///   - name: Function name to invoke
    ///   - payload: Request payload as dictionary
    /// - Returns: Decoded response of type T
    /// - Throws: Function call or decoding errors
    func call<T: Decodable>(_ name: String, payload: [String: Any] = [:]) async throws -> T {
        try await callWithRetry(name: name, payload: payload)
    }

    /// Call Firebase Cloud Function with exponential backoff retry
    /// - Parameters:
    ///   - name: Function name to invoke
    ///   - payload: Request payload as dictionary
    ///   - attempt: Current attempt number (internal use)
    ///   - startTime: Start time for telemetry tracking (internal use)
    /// - Returns: Decoded response of type T
    /// - Throws: Function call or decoding errors after all retries exhausted
    private func callWithRetry<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        attempt: Int = 1,
        startTime: Date? = nil
    ) async throws -> T {
        isProcessing = true
        errorMessage = nil

        // Track start time on first attempt
        let callStartTime = startTime ?? Date()
        let userId = authService?.currentUser?.id

        defer {
            if attempt >= RetryConfig.maxAttempts {
                isProcessing = false
            }
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

            #if DEBUG
            if attempt > 1 {
                print("[AIFeaturesService] '\(name)' succeeded on attempt \(attempt)")
            }
            #endif

            // Log successful telemetry
            let telemetryEvent = TelemetryEvent(
                userId: userId,
                functionName: name,
                startTime: callStartTime,
                endTime: Date(),
                success: true,
                attemptCount: attempt
            )
            logTelemetry(telemetryEvent)

            return decoded
        } catch {
            let detailedError: String
            let shouldRetry = isRetryableError(error)

            if let decodingError = error as? DecodingError {
                detailedError = formatDecodingError(decodingError)
                print("[AIFeaturesService] Decoding error for '\(name)': \(detailedError)")
            } else {
                detailedError = error.localizedDescription
                print("[AIFeaturesService] Error calling '\(name)' (attempt \(attempt)/\(RetryConfig.maxAttempts)): \(detailedError)")
            }

            // Check if we should retry
            if shouldRetry && attempt < RetryConfig.maxAttempts {
                // Calculate exponential backoff delay
                let delayNanoseconds = calculateBackoffDelay(for: attempt)

                #if DEBUG
                print("[AIFeaturesService] Retrying '\(name)' after \(Double(delayNanoseconds) / 1_000_000_000)s delay...")
                #endif

                // Wait before retry
                try await Task.sleep(nanoseconds: delayNanoseconds)

                // Recursive retry (pass through startTime for accurate telemetry)
                return try await callWithRetry(name: name, payload: payload, attempt: attempt + 1, startTime: callStartTime)
            }

            // No more retries - log failure telemetry
            let errorType = String(describing: type(of: error))
            let telemetryEvent = TelemetryEvent(
                userId: userId,
                functionName: name,
                startTime: callStartTime,
                endTime: Date(),
                success: false,
                attemptCount: attempt,
                errorType: errorType,
                errorMessage: detailedError
            )
            logTelemetry(telemetryEvent)

            // Surface error
            errorMessage = detailedError
            throw error
        }
    }

    /// Determine if an error is retryable (network/transient errors)
    /// - Parameter error: The error to check
    /// - Returns: True if the error is retryable
    private func isRetryableError(_ error: Error) -> Bool {
        // Don't retry decoding errors - these indicate response schema issues
        if error is DecodingError {
            return false
        }

        // Don't retry invalid response errors - these indicate backend issues
        if let aiError = error as? AIFeaturesError, aiError == .invalidResponse {
            return false
        }

        // Check for NSError with network-related codes
        let nsError = error as NSError

        // Retry on network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }

        // Retry on Functions-specific errors (INTERNAL, UNAVAILABLE, DEADLINE_EXCEEDED)
        if nsError.domain == "FIRFunctionsErrorDomain" {
            // FunctionsErrorCode: internal = 13, unavailable = 14, deadlineExceeded = 4
            switch nsError.code {
            case 4, 13, 14:
                return true
            default:
                return false
            }
        }

        // Don't retry by default
        return false
    }

    /// Calculate exponential backoff delay with jitter
    /// - Parameter attempt: Current attempt number
    /// - Returns: Delay in nanoseconds
    private func calculateBackoffDelay(for attempt: Int) -> UInt64 {
        // Exponential backoff: base * 2^(attempt-1)
        let exponentialDelay = RetryConfig.baseDelayNanoseconds * UInt64(pow(2.0, Double(attempt - 1)))

        // Cap at max delay
        let cappedDelay = min(exponentialDelay, RetryConfig.maxDelayNanoseconds)

        // Add jitter (±25% randomness) to avoid thundering herd
        let jitterRange = Double(cappedDelay) * 0.25
        let jitter = Double.random(in: -jitterRange...jitterRange)
        let finalDelay = UInt64(max(0, Double(cappedDelay) + jitter))

        return finalDelay
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
        prefetchedConversations.removeAll()
        schedulingIntentDetected.removeAll()
        schedulingIntentConfidence.removeAll()
        lastPrefetchTimestamps.removeAll()
        pendingSchedulingSuggestions.removeAll()
    }

    /// Reset service state (called on sign-out)
    func reset() {
        clearCaches()
        isProcessing = false
        errorMessage = nil
        searchLoadingState = false
        searchError = nil

        // Clear all cached data from SwiftData
        clearSearchDataFromSwiftData()
        clearCoordinationDataFromSwiftData()
    }

    /// Clear expired cached data from SwiftData (call periodically or on app lifecycle events)
    /// This is a non-destructive cleanup that only removes stale data
    func clearExpiredCachedData() {
        do {
            try clearExpiredThreadSummaries()
            try clearExpiredSearchResults()
            #if DEBUG
            print("[AIFeaturesService] Periodic cleanup of expired cached data completed")
            #endif
        } catch {
            #if DEBUG
            print("[AIFeaturesService] Error during periodic cleanup: \(error.localizedDescription)")
            #endif
        }
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

    /// Clear coordination-related data from SwiftData (insights and alerts)
    private func clearCoordinationDataFromSwiftData() {
        guard let modelContext = modelContext else { return }

        do {
            // Delete all CoordinationInsightEntity instances
            let insightsDescriptor = FetchDescriptor<CoordinationInsightEntity>()
            let insights = try modelContext.fetch(insightsDescriptor)
            for insight in insights {
                modelContext.delete(insight)
            }

            // Delete all ProactiveAlertEntity instances
            let alertsDescriptor = FetchDescriptor<ProactiveAlertEntity>()
            let alerts = try modelContext.fetch(alertsDescriptor)
            for alert in alerts {
                modelContext.delete(alert)
            }

            try modelContext.save()

            #if DEBUG
            print("[AIFeaturesService] Cleared \(insights.count) coordination insights and \(alerts.count) proactive alerts from SwiftData")
            #endif
        } catch {
            print("[AIFeaturesService] Error clearing coordination data: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle Hooks

    /// Called when user signs in
    func onSignIn() {
        // Refresh coordination insights on sign-in
        Task { @MainActor [weak self] in
            await self?.refreshCoordinationInsights()
        }
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
        #if DEBUG
        print("[AIFeaturesService] Message mutation: conversation=\(conversationId), message=\(messageId)")
        #endif

        // Detect scheduling intent and auto-prefetch meeting suggestions
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.handleSchedulingIntentDetection(conversationId: conversationId, messageId: messageId)
        }

        // Future implementations will trigger other AI analysis here:
        // - Check for action items
        // - Update priority scores
        // - Track decisions
    }

    /// Handle scheduling intent detection and auto-prefetch meeting suggestions
    /// - Parameters:
    ///   - conversationId: The ID of the conversation
    ///   - messageId: The ID of the message
    private func handleSchedulingIntentDetection(conversationId: String, messageId: String) async {
        // Check if suggestions are currently snoozed
        if isSchedulingSuggestionsSnoozed(for: conversationId) {
            #if DEBUG
            print("[AIFeaturesService] Scheduling suggestions snoozed for conversation \(conversationId)")
            #endif
            return
        }

        // Check debounce: don't prefetch if we recently did
        if let lastPrefetch = lastPrefetchTimestamps[conversationId] {
            let timeSinceLastPrefetch = Date().timeIntervalSince(lastPrefetch)
            if timeSinceLastPrefetch < debounceInterval {
                #if DEBUG
                print("[AIFeaturesService] Debouncing prefetch for conversation \(conversationId) (last: \(Int(timeSinceLastPrefetch))s ago)")
                #endif
                return
            }
        }

        // Don't prefetch if we've already done it for this conversation (legacy check)
        guard !prefetchedConversations.contains(conversationId) else {
            return
        }

        // Fetch the message entity to check for scheduling intent
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == messageId
            }
        )

        guard let message = try? modelContext.fetch(descriptor).first else {
            return
        }

        // Check if message has scheduling intent with sufficient confidence
        // Confidence threshold: 0.6 (same as backend threshold in detectSchedulingIntent)
        guard let intent = message.schedulingIntent,
              let confidence = message.intentConfidence,
              confidence >= 0.6,
              intent != "none" else {
            return
        }

        #if DEBUG
        print("[AIFeaturesService] Scheduling intent detected (confidence: \(confidence)) in conversation \(conversationId)")
        #endif

        // Update observable state for UI
        schedulingIntentDetected[conversationId] = true
        schedulingIntentConfidence[conversationId] = confidence

        // Fetch conversation to get participant IDs
        let convDescriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )

        guard let conversation = try? modelContext.fetch(convDescriptor).first else {
            return
        }

        // Filter out bot participants (those with "bot:" prefix)
        let humanParticipants = conversation.participantIds.filter { !$0.hasPrefix("bot:") }

        // Only prefetch for multi-participant conversations (excluding bots)
        guard humanParticipants.count >= 2 else {
            #if DEBUG
            print("[AIFeaturesService] Skipping prefetch - not enough human participants (\(humanParticipants.count))")
            #endif
            return
        }

        // Check network connectivity before attempting fetch
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[AIFeaturesService] Network offline - queueing scheduling suggestion for conversation \(conversationId)")
            #endif
            // Queue for retry when network returns
            let pending = PendingSchedulingSuggestion(
                conversationId: conversationId,
                messageId: messageId,
                timestamp: Date()
            )
            pendingSchedulingSuggestions.insert(pending)
            return
        }

        // Mark as prefetched to prevent duplicates
        prefetchedConversations.insert(conversationId)

        // Record timestamp for debouncing
        lastPrefetchTimestamps[conversationId] = Date()

        // Auto-prefetch meeting suggestions (default 60 minute meeting)
        do {
            #if DEBUG
            print("[AIFeaturesService] Auto-prefetching meeting suggestions for conversation \(conversationId)")
            #endif

            _ = try await suggestMeetingTimes(
                conversationId: conversationId,
                participantIds: humanParticipants,
                durationMinutes: 60,
                preferredDays: 14,
                forceRefresh: false
            )

            #if DEBUG
            print("[AIFeaturesService] Successfully prefetched meeting suggestions for conversation \(conversationId)")
            #endif
        } catch {
            #if DEBUG
            print("[AIFeaturesService] Failed to prefetch meeting suggestions: \(error.localizedDescription)")
            #endif
            // Remove from prefetched set and timestamp so we can retry later
            prefetchedConversations.remove(conversationId)
            lastPrefetchTimestamps.removeValue(forKey: conversationId)

            // If error was network-related, queue for retry
            if !networkMonitor.isConnected {
                let pending = PendingSchedulingSuggestion(
                    conversationId: conversationId,
                    messageId: messageId,
                    timestamp: Date()
                )
                pendingSchedulingSuggestions.insert(pending)
            }
        }
    }

    /// Process pending scheduling suggestion requests when network returns
    /// Should be called when network connectivity is restored
    func processPendingSchedulingSuggestions() async {
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[AIFeaturesService] Network still offline - cannot process pending suggestions")
            #endif
            return
        }

        guard !pendingSchedulingSuggestions.isEmpty else {
            return
        }

        #if DEBUG
        print("[AIFeaturesService] Processing \(pendingSchedulingSuggestions.count) pending scheduling suggestions")
        #endif

        // Process all pending requests
        let pending = Array(pendingSchedulingSuggestions)
        pendingSchedulingSuggestions.removeAll()

        for request in pending {
            // Re-trigger detection for each pending request
            await handleSchedulingIntentDetection(
                conversationId: request.conversationId,
                messageId: request.messageId
            )
        }

        #if DEBUG
        print("[AIFeaturesService] Finished processing pending scheduling suggestions")
        #endif
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
            // Update existing summary and reset TTL
            existing.summary = summary
            existing.keyPoints = keyPoints
            existing.generatedAt = generatedAt
            existing.messageCount = messageCount
            existing.updatedAt = Date()
            existing.expiresAt = Date().addingTimeInterval(24 * 60 * 60) // Reset 24h TTL
        } else {
            // Create new summary (TTL set by default in init)
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

    /// Fetch the most recent thread summary for a conversation (non-expired only)
    /// - Parameter conversationId: The conversation to fetch summary for
    /// - Returns: ThreadSummaryEntity if one exists and is not expired, nil otherwise
    func fetchThreadSummary(for conversationId: String) -> ThreadSummaryEntity? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        guard let summary = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        // Check if expired
        if summary.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Summary for \(conversationId) expired, returning nil")
            #endif
            return nil
        }

        return summary
    }

    /// Clear expired thread summaries from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredThreadSummaries() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ThreadSummaryEntity>()
        let allSummaries = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for summary in allSummaries where summary.isExpired {
            modelContext.delete(summary)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired thread summaries")
            #endif
        }
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

    // MARK: - Search Results Persistence

    /// Fetch search results from local storage for a given query
    /// - Parameter query: The search query
    /// - Returns: Array of non-expired SearchResultEntity instances, or nil if none found or all expired
    func fetchSearchResults(for query: String) -> [SearchResultEntity]? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<SearchResultEntity>(
            predicate: #Predicate { $0.query == query },
            sortBy: [SortDescriptor(\.rank)]
        )

        guard let results = try? modelContext.fetch(descriptor), !results.isEmpty else {
            return nil
        }

        // Filter out expired results
        let validResults = results.filter { !$0.isExpired }

        if validResults.isEmpty {
            #if DEBUG
            print("[AIFeaturesService] All search results for '\(query)' expired, returning nil")
            #endif
            return nil
        }

        return validResults
    }

    /// Clear expired search results from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredSearchResults() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<SearchResultEntity>()
        let allResults = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for result in allResults where result.isExpired {
            modelContext.delete(result)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired search results")
            #endif
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

        // Check in-memory cache first unless force refresh is requested
        if !forceRefresh,
           let cached = searchCache[trimmedQuery],
           !cached.isExpired {
            #if DEBUG
            print("[AIFeaturesService] Returning in-memory cached search results for query: \(trimmedQuery)")
            #endif
            return cached.results
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localResults = fetchSearchResults(for: trimmedQuery) {
            #if DEBUG
            print("[AIFeaturesService] Returning local search results for query: \(trimmedQuery) (\(localResults.count) results)")
            #endif
            // Update memory cache
            searchCache[trimmedQuery] = CachedSearchResults(
                query: trimmedQuery,
                results: localResults,
                cachedAt: Date()
            )
            return localResults
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

            // Delete any existing search results for this query (including expired ones)
            let existingDescriptor = FetchDescriptor<SearchResultEntity>(
                predicate: #Predicate { $0.query == trimmedQuery }
            )
            if let existingResults = try? modelContext.fetch(existingDescriptor) {
                for existing in existingResults {
                    modelContext.delete(existing)
                }
            }

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
    func saveMeetingSuggestions(response: MeetingSuggestionsResponse) throws {
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
            let analyticsRef = firestoreService.firestore
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
            let summaryRef = firestoreService.firestore
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

    // MARK: - Scheduling Suggestion Snooze Management

    /// Save snooze state for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation to snooze
    ///   - duration: Duration in seconds to snooze (default: 1 hour)
    /// - Throws: SwiftData persistence errors
    func snoozeSchedulingSuggestions(for conversationId: String, duration: TimeInterval = 3600) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let snoozedUntil = Date().addingTimeInterval(duration)

        // Check if snooze already exists
        let descriptor = FetchDescriptor<SchedulingSuggestionSnoozeEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing snooze
            existing.snoozedUntil = snoozedUntil
            existing.updatedAt = Date()
        } else {
            // Create new snooze
            let snooze = SchedulingSuggestionSnoozeEntity(
                conversationId: conversationId,
                snoozedUntil: snoozedUntil
            )
            modelContext.insert(snooze)
        }

        try modelContext.save()

        #if DEBUG
        print("[AIFeaturesService] Snoozed scheduling suggestions for conversation \(conversationId) until \(snoozedUntil)")
        #endif
    }

    /// Check if scheduling suggestions are snoozed for a conversation
    /// - Parameter conversationId: The conversation to check
    /// - Returns: True if currently snoozed, false otherwise
    func isSchedulingSuggestionsSnoozed(for conversationId: String) -> Bool {
        guard let modelContext = modelContext else { return false }

        let descriptor = FetchDescriptor<SchedulingSuggestionSnoozeEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        guard let snooze = try? modelContext.fetch(descriptor).first else {
            return false
        }

        if snooze.isExpired {
            // Clean up expired snooze
            modelContext.delete(snooze)
            try? modelContext.save()
            return false
        }

        return snooze.isSnoozed
    }

    /// Clear snooze state for a conversation
    /// - Parameter conversationId: The conversation to clear snooze for
    /// - Throws: SwiftData persistence errors
    func clearSchedulingSuggestionsSnooze(for conversationId: String) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<SchedulingSuggestionSnoozeEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()

            #if DEBUG
            print("[AIFeaturesService] Cleared snooze for conversation \(conversationId)")
            #endif
        }
    }

    /// Clear all expired snoozes from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredSnoozes() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<SchedulingSuggestionSnoozeEntity>()
        let allSnoozes = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for snooze in allSnoozes where snooze.isExpired {
            modelContext.delete(snooze)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired snoozes")
            #endif
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
        Task.detached {
            do {
                let result = try await operation()
                await onComplete(.success(result))
            } catch {
                await onComplete(.failure(error))
            }
        }
    }

    /// Example method showing background task pattern for future AI features
    func analyzeConversationInBackground(conversationId: String) {
        performBackgroundAIAnalysis(conversationId: conversationId) {
            // This is where the actual AI callable would be invoked
            // For now, return a placeholder
            return "Analysis placeholder"
        } onComplete: { @MainActor [weak self] result in
            // MainActor-isolated completion handler
            guard let self else { return }
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
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - AI Feedback Submission

    /// Feedback entry for AI-generated content
    struct AIFeedback: Codable {
        let feedbackId: String
        let userId: String
        let conversationId: String
        let featureType: String  // "summary", "action_items", "search", "meeting_suggestions"
        let originalContent: String
        let userCorrection: String?
        let rating: Int?  // 1-5 stars
        let comment: String?
        let timestamp: Date
        let metadata: [String: String]?

        init(
            userId: String,
            conversationId: String,
            featureType: String,
            originalContent: String,
            userCorrection: String? = nil,
            rating: Int? = nil,
            comment: String? = nil,
            metadata: [String: String]? = nil
        ) {
            self.feedbackId = UUID().uuidString
            self.userId = userId
            self.conversationId = conversationId
            self.featureType = featureType
            self.originalContent = originalContent
            self.userCorrection = userCorrection
            self.rating = rating
            self.comment = comment
            self.timestamp = Date()
            self.metadata = metadata
        }

        func toDictionary() -> [String: Any] {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(self),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return dict
        }
    }

    /// Submit user feedback for AI-generated content
    /// - Parameter feedback: The feedback to submit
    /// - Throws: Firestore errors
    func submitAIFeedback(_ feedback: AIFeedback) async throws {
        guard let firestoreService = firestoreService else {
            throw AIFeaturesError.notConfigured
        }

        let db = firestoreService.firestore
        let collectionRef = db.collection("ai_feedback")

        try await collectionRef.document(feedback.feedbackId).setData(feedback.toDictionary())

        #if DEBUG
        print("[AIFeaturesService] Submitted AI feedback: \(feedback.featureType) for conversation \(feedback.conversationId)")
        #endif
    }

    // MARK: - Coordination Insights Sync

    /// Sync coordination insights from Firestore to local SwiftData storage
    /// - Throws: Firestore or SwiftData errors
    func syncCoordinationInsights() async throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        guard let currentUser = Auth.auth().currentUser else {
            throw AIFeaturesError.unauthorized
        }

        #if DEBUG
        print("[AIFeaturesService] Starting coordination insights sync")
        #endif

        // Fetch insights from Firestore coordinationInsights collection
        let snapshot = try await firestore.collection("coordinationInsights").getDocuments()

        var syncedCount = 0
        var dedupedCount = 0

        for document in snapshot.documents {
            let data = document.data()

            // Extract fields from Firestore document
            guard let conversationId = data["conversationId"] as? String,
                  let teamId = data["teamId"] as? String,
                  let summary = data["summary"] as? String,
                  let overallHealthStr = data["overallHealth"] as? String,
                  let generatedAtTimestamp = data["generatedAt"] as? Timestamp,
                  let expiresAtTimestamp = data["expiresAt"] as? Timestamp else {
                #if DEBUG
                print("[AIFeaturesService] Skipping malformed insight document: \(document.documentID)")
                #endif
                continue
            }

            // Check if already exists (dedupe by conversationId)
            let descriptor = FetchDescriptor<CoordinationInsightEntity>(
                predicate: #Predicate { $0.conversationId == conversationId }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                // Update if newer
                if generatedAtTimestamp.dateValue() > existing.generatedAt {
                    updateCoordinationInsight(existing, with: data)
                    syncedCount += 1
                } else {
                    dedupedCount += 1
                }
                continue
            }

            // Create new entity
            let insight = try createCoordinationInsight(from: data, documentId: document.documentID)
            modelContext.insert(insight)
            syncedCount += 1
        }

        if syncedCount > 0 {
            try modelContext.save()
        }

        #if DEBUG
        print("[AIFeaturesService] Coordination insights sync complete: \(syncedCount) synced, \(dedupedCount) deduplicated")
        #endif
    }

    /// Create a CoordinationInsightEntity from Firestore data
    private func createCoordinationInsight(
        from data: [String: Any],
        documentId: String
    ) throws -> CoordinationInsightEntity {
        guard let conversationId = data["conversationId"] as? String,
              let teamId = data["teamId"] as? String,
              let summary = data["summary"] as? String,
              let overallHealthStr = data["overallHealth"] as? String,
              let generatedAtTimestamp = data["generatedAt"] as? Timestamp,
              let expiresAtTimestamp = data["expiresAt"] as? Timestamp else {
            throw AIFeaturesError.invalidResponse
        }

        let overallHealth = CoordinationHealth(rawValue: overallHealthStr) ?? .good

        // Parse nested arrays
        let actionItems = parseActionItems(from: data["actionItems"])
        let staleDecisions = parseStaleDecisions(from: data["staleDecisions"])
        let upcomingDeadlines = parseUpcomingDeadlines(from: data["upcomingDeadlines"])
        let schedulingConflicts = parseSchedulingConflicts(from: data["schedulingConflicts"])
        let blockers = parseBlockers(from: data["blockers"])

        return CoordinationInsightEntity(
            id: documentId,
            conversationId: conversationId,
            teamId: teamId,
            actionItems: actionItems,
            staleDecisions: staleDecisions,
            upcomingDeadlines: upcomingDeadlines,
            schedulingConflicts: schedulingConflicts,
            blockers: blockers,
            summary: summary,
            overallHealth: overallHealth,
            generatedAt: generatedAtTimestamp.dateValue(),
            expiresAt: expiresAtTimestamp.dateValue()
        )
    }

    /// Update existing CoordinationInsightEntity with new data
    private func updateCoordinationInsight(_ entity: CoordinationInsightEntity, with data: [String: Any]) {
        if let summary = data["summary"] as? String {
            entity.summary = summary
        }
        if let overallHealthStr = data["overallHealth"] as? String,
           let health = CoordinationHealth(rawValue: overallHealthStr) {
            entity.overallHealth = health
        }
        if let generatedAtTimestamp = data["generatedAt"] as? Timestamp {
            entity.generatedAt = generatedAtTimestamp.dateValue()
        }
        if let expiresAtTimestamp = data["expiresAt"] as? Timestamp {
            entity.expiresAt = expiresAtTimestamp.dateValue()
        }

        entity.actionItems = parseActionItems(from: data["actionItems"])
        entity.staleDecisions = parseStaleDecisions(from: data["staleDecisions"])
        entity.upcomingDeadlines = parseUpcomingDeadlines(from: data["upcomingDeadlines"])
        entity.schedulingConflicts = parseSchedulingConflicts(from: data["schedulingConflicts"])
        entity.blockers = parseBlockers(from: data["blockers"])
        entity.updatedAt = Date()
    }

    // MARK: - Coordination Insight Parsing Helpers

    private func parseActionItems(from value: Any?) -> [CoordinationActionItem] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let description = dict["description"] as? String,
                  let status = dict["status"] as? String else {
                return nil
            }
            return CoordinationActionItem(
                description: description,
                assignee: dict["assignee"] as? String,
                deadline: dict["deadline"] as? String,
                status: status
            )
        }
    }

    private func parseStaleDecisions(from value: Any?) -> [StaleDecision] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let topic = dict["topic"] as? String,
                  let lastMentioned = dict["lastMentioned"] as? String,
                  let reason = dict["reason"] as? String else {
                return nil
            }
            return StaleDecision(topic: topic, lastMentioned: lastMentioned, reason: reason)
        }
    }

    private func parseUpcomingDeadlines(from value: Any?) -> [UpcomingDeadline] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let description = dict["description"] as? String,
                  let dueDate = dict["dueDate"] as? String,
                  let urgency = dict["urgency"] as? String else {
                return nil
            }
            return UpcomingDeadline(description: description, dueDate: dueDate, urgency: urgency)
        }
    }

    private func parseSchedulingConflicts(from value: Any?) -> [SchedulingConflict] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let description = dict["description"] as? String,
                  let participants = dict["participants"] as? [String] else {
                return nil
            }
            return SchedulingConflict(description: description, participants: participants)
        }
    }

    private func parseBlockers(from value: Any?) -> [Blocker] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let description = dict["description"] as? String else {
                return nil
            }
            return Blocker(description: description, blockedBy: dict["blockedBy"] as? String)
        }
    }

    /// Fetch coordination insights for a conversation from local SwiftData
    /// - Parameter conversationId: The conversation to fetch insights for
    /// - Returns: CoordinationInsightEntity if one exists and is not expired, nil otherwise
    func fetchCoordinationInsights(for conversationId: String) -> CoordinationInsightEntity? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        guard let insight = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        // Return nil if expired
        return insight.isExpired ? nil : insight
    }

    /// Fetch all active coordination insights from local SwiftData
    /// - Returns: Array of non-expired CoordinationInsightEntity instances
    func fetchAllCoordinationInsights() -> [CoordinationInsightEntity] {
        guard let modelContext = modelContext else { return [] }

        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        let allInsights = (try? modelContext.fetch(descriptor)) ?? []
        return allInsights.filter { !$0.isExpired }
    }

    /// Clear expired coordination insights from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredCoordinationInsights() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<CoordinationInsightEntity>()
        let allInsights = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for insight in allInsights where insight.isExpired {
            modelContext.delete(insight)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired coordination insights")
            #endif
        }
    }

    // MARK: - Proactive Alerts Management

    /// Fetch active proactive alerts from local SwiftData
    /// - Parameter conversationId: Optional conversation filter
    /// - Returns: Array of active ProactiveAlertEntity instances
    func fetchProactiveAlerts(for conversationId: String? = nil) -> [ProactiveAlertEntity] {
        guard let modelContext = modelContext else { return [] }

        let descriptor: FetchDescriptor<ProactiveAlertEntity>
        if let conversationId = conversationId {
            descriptor = FetchDescriptor<ProactiveAlertEntity>(
                predicate: #Predicate { $0.conversationId == conversationId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<ProactiveAlertEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }

        let allAlerts = (try? modelContext.fetch(descriptor)) ?? []
        return allAlerts.filter { $0.isActive }
    }

    /// Mark a proactive alert as read
    /// - Parameter alertId: The alert ID to mark as read
    /// - Throws: SwiftData persistence errors
    func markAlertAsRead(_ alertId: String) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ProactiveAlertEntity>(
            predicate: #Predicate { $0.id == alertId }
        )

        guard let alert = try modelContext.fetch(descriptor).first else {
            return
        }

        alert.isRead = true
        alert.readAt = Date()
        try modelContext.save()
    }

    /// Dismiss a proactive alert
    /// - Parameter alertId: The alert ID to dismiss
    /// - Throws: SwiftData persistence errors
    func dismissAlert(_ alertId: String) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ProactiveAlertEntity>(
            predicate: #Predicate { $0.id == alertId }
        )

        guard let alert = try modelContext.fetch(descriptor).first else {
            return
        }

        alert.isDismissed = true
        alert.dismissedAt = Date()
        try modelContext.save()
    }

    /// Clear expired proactive alerts from local storage
    /// - Throws: SwiftData persistence errors
    func clearExpiredProactiveAlerts() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<ProactiveAlertEntity>()
        let allAlerts = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for alert in allAlerts where alert.isExpired {
            modelContext.delete(alert)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[AIFeaturesService] Cleared \(deletedCount) expired proactive alerts")
            #endif
        }
    }

    // MARK: - Background Refresh

    /// Trigger coordination analysis via Cloud Function
    /// This manually runs the coordination analysis that normally runs every 60 minutes
    /// - Returns: Analysis result with counts of insights generated
    /// - Throws: Firebase function call errors
    private func triggerCoordinationAnalysis() async throws -> CoordinationAnalysisResult {
        #if DEBUG
        print("[AIFeaturesService] Triggering coordination analysis via Cloud Function")
        #endif

        let response: CoordinationAnalysisResult = try await call("triggerCoordinationAnalysis")

        #if DEBUG
        print("[AIFeaturesService] Coordination analysis complete: \(response.conversationsAnalyzed) conversations, \(response.insightsGenerated) insights")
        #endif

        return response
    }

    /// Refresh coordination insights from Firestore and clean up expired data
    /// When forceAnalysis is true, triggers Cloud Function to regenerate insights
    /// Call this on app foreground or when network connectivity returns
    /// - Parameter forceAnalysis: If true, triggers new analysis via Cloud Function before syncing
    func refreshCoordinationInsights(forceAnalysis: Bool = false) async {
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[AIFeaturesService] Network offline - skipping coordination insights refresh")
            #endif
            return
        }

        guard authService?.currentUser != nil else {
            #if DEBUG
            print("[AIFeaturesService] No user logged in - skipping coordination insights refresh")
            #endif
            return
        }

        #if DEBUG
        print("[AIFeaturesService] Refreshing coordination insights from Firestore (forceAnalysis: \(forceAnalysis))")
        #endif

        do {
            // If forceAnalysis, trigger new analysis via Cloud Function first
            if forceAnalysis {
                let result = try await triggerCoordinationAnalysis()
                #if DEBUG
                print("[AIFeaturesService] Triggered analysis: \(result.insightsGenerated) insights generated")
                #endif
            }

            // Sync latest insights from Firestore (includes newly generated ones)
            try await syncCoordinationInsights()

            // Clean up expired data
            try clearExpiredCoordinationInsights()
            try clearExpiredProactiveAlerts()

            #if DEBUG
            print("[AIFeaturesService] Coordination insights refresh complete")
            #endif
        } catch {
            #if DEBUG
            print("[AIFeaturesService] Failed to refresh coordination insights: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to refresh coordination insights: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Models

/// Response from triggerCoordinationAnalysis Cloud Function
struct CoordinationAnalysisResult: Codable {
    let success: Bool
    let conversationsAnalyzed: Int
    let insightsGenerated: Int
    let errors: Int
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case success
        case conversationsAnalyzed = "conversations_analyzed"
        case insightsGenerated = "insights_generated"
        case errors
        case timestamp
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
