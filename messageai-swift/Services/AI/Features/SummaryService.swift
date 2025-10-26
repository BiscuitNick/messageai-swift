//
//  SummaryService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Service responsible for thread summarization features
@MainActor
@Observable
final class SummaryService {

    // MARK: - Public State

    /// Per-conversation loading states and errors
    let state = FeatureState<ThreadSummaryResponse>()

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private weak var authService: AuthCoordinator?
    private weak var modelContext: ModelContext?

    // MARK: - Cache

    private let cache: CacheManager<CachedSummary>

    // MARK: - Initialization

    init(
        functionClient: FirebaseFunctionClient,
        telemetryLogger: TelemetryLogger
    ) {
        self.functionClient = functionClient
        self.telemetryLogger = telemetryLogger
        self.cache = CacheManager<CachedSummary>()
    }

    // MARK: - Configuration

    func configure(
        authService: AuthCoordinator,
        modelContext: ModelContext
    ) {
        self.authService = authService
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Generate a summary for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation to summarize
    ///   - messageLimit: Maximum number of messages to include (default: 50)
    ///   - saveLocally: Whether to save the summary to local SwiftData storage (default: true)
    ///   - forceRefresh: Force a new summary even if cache is valid (default: false)
    /// - Returns: ThreadSummaryResponse with the generated summary
    /// - Throws: AIFeaturesError or network errors
    func summarizeThread(
        conversationId: String,
        messageLimit: Int = 50,
        saveLocally: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> ThreadSummaryResponse {
        // Verify user is authenticated
        guard let userId = authService?.currentUser?.id else {
            state.setError(conversationId, AIFeaturesError.unauthorized.errorDescription)
            throw AIFeaturesError.unauthorized
        }

        // Set loading state
        state.setLoading(conversationId, true)
        state.setError(conversationId, nil)

        defer {
            state.setLoading(conversationId, false)
        }

        // Check in-memory cache first unless force refresh is requested
        if !forceRefresh, let cached = cache.get(conversationId) {
            #if DEBUG
            print("[SummaryService] Returning cached summary for conversation \(conversationId)")
            #endif

            // Log cache hit to telemetry
            telemetryLogger.logSuccess(
                functionName: "summarizeThreadTask",
                userId: userId,
                startTime: Date(),
                endTime: Date(),
                attemptCount: 1,
                cacheHit: true
            )

            return cached.response
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localSummary = fetchThreadSummary(for: conversationId) {
            // Check if local summary is recent enough (within 1 hour)
            let age = Date().timeIntervalSince(localSummary.generatedAt)
            if age < 3600 {
                #if DEBUG
                print("[SummaryService] Returning local summary for conversation \(conversationId)")
                #endif
                let response = ThreadSummaryResponse(
                    summary: localSummary.summary,
                    keyPoints: localSummary.keyPoints,
                    conversationId: localSummary.conversationId,
                    timestamp: localSummary.generatedAt,
                    messageCount: localSummary.messageCount
                )
                // Update memory cache
                cache.set(conversationId, value: CachedSummary(response: response, cachedAt: Date()))
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
            let response: ThreadSummaryResponse = try await functionClient.call(
                "summarizeThreadTask",
                payload: payload,
                userId: userId
            )

            // Update memory cache
            cache.set(conversationId, value: CachedSummary(response: response, cachedAt: Date()))

            // Update state
            state.set(conversationId, response)

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
                    print("[SummaryService] Failed to save summary locally: \(error)")
                    #endif
                }
            }

            return response
        } catch {
            state.setError(conversationId, error.localizedDescription)
            throw error
        }
    }

    // MARK: - Cache Management

    /// Clear all in-memory caches
    func clearCache() {
        cache.clear()
        state.clearAll()
    }

    /// Clear cache for a specific conversation
    func clearCache(for conversationId: String) {
        cache.remove(conversationId)
        state.clear(conversationId)
    }

    // MARK: - SwiftData Persistence

    /// Save a thread summary to local SwiftData storage
    private func saveThreadSummary(
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
            print("[SummaryService] Summary for \(conversationId) expired, returning nil")
            #endif
            return nil
        }

        return summary
    }

    /// Clear expired thread summaries from local storage
    func clearExpiredSummaries() throws {
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
            print("[SummaryService] Cleared \(deletedCount) expired thread summaries")
            #endif
        }
    }

    /// Delete a thread summary from local storage
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
}

// MARK: - Cache Model

/// Cached summary entry with expiration
struct CachedSummary: Cacheable {
    let response: ThreadSummaryResponse
    let cachedAt: Date

    var isExpired: Bool {
        // Cache expires after 1 hour
        Date().timeIntervalSince(cachedAt) > 3600
    }
}
