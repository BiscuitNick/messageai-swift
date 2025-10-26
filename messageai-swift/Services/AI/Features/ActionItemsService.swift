//
//  ActionItemsService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Service responsible for action item extraction features
@MainActor
@Observable
final class ActionItemsService {

    // MARK: - Public State

    /// Per-conversation loading states and errors
    let state = FeatureState<ActionItemsResponse>()

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private weak var authService: AuthCoordinator?
    private weak var modelContext: ModelContext?

    // MARK: - Cache

    private let cache: CacheManager<CachedActionItems>

    // MARK: - Initialization

    init(
        functionClient: FirebaseFunctionClient,
        telemetryLogger: TelemetryLogger
    ) {
        self.functionClient = functionClient
        self.telemetryLogger = telemetryLogger
        self.cache = CacheManager<CachedActionItems>()
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

    /// Extract action items from a conversation
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

        // Check cache first unless force refresh is requested
        if !forceRefresh, let cached = cache.get(conversationId) {
            #if DEBUG
            print("[ActionItemsService] Returning cached action items for conversation \(conversationId)")
            #endif

            // Log cache hit to telemetry
            telemetryLogger.logSuccess(
                functionName: "extractActionItems",
                userId: userId,
                startTime: Date(),
                endTime: Date(),
                attemptCount: 1,
                cacheHit: true
            )

            return cached.response
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "conversationId": conversationId,
                "windowDays": windowDays,
            ]

            // Call the Firebase Cloud Function
            let response: ActionItemsResponse = try await functionClient.call(
                "extractActionItems",
                payload: payload,
                userId: userId
            )

            // Update memory cache
            cache.set(conversationId, value: CachedActionItems(response: response, cachedAt: Date()))

            // Update state
            state.set(conversationId, response)

            // Note: Firestore listener will automatically sync the action items to SwiftData
            // The Cloud Function writes to Firestore, which triggers the listener in FirestoreService

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
}

// MARK: - Cache Model

/// Cached action items entry with expiration
struct CachedActionItems: Cacheable {
    let response: ActionItemsResponse
    let cachedAt: Date

    var isExpired: Bool {
        // Cache expires after 1 hour
        Date().timeIntervalSince(cachedAt) > 3600
    }
}
