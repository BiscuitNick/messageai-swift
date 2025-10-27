//
//  MeetingSuggestionsService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Service responsible for meeting time suggestions
@MainActor
@Observable
final class MeetingSuggestionsService {

    // MARK: - Public State

    /// Per-conversation loading states and errors
    let state = FeatureState<MeetingSuggestionsResponse>()

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private weak var authService: AuthCoordinator?
    private weak var modelContext: ModelContext?
    private weak var firestoreService: FirestoreCoordinator?

    // MARK: - Cache

    private let cache: CacheManager<CachedMeetingSuggestions>

    // MARK: - Initialization

    init(
        functionClient: FirebaseFunctionClient,
        telemetryLogger: TelemetryLogger
    ) {
        self.functionClient = functionClient
        self.telemetryLogger = telemetryLogger
        self.cache = CacheManager<CachedMeetingSuggestions>()
    }

    // MARK: - Configuration

    func configure(
        authService: AuthCoordinator,
        modelContext: ModelContext,
        firestoreService: FirestoreCoordinator
    ) {
        self.authService = authService
        self.modelContext = modelContext
        self.firestoreService = firestoreService
    }

    // MARK: - Public API

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
            print("[MeetingSuggestionsService] Returning cached meeting suggestions for conversation \(conversationId)")
            #endif

            // Log cache hit to telemetry
            telemetryLogger.logSuccess(
                functionName: "suggestMeetingTimes",
                userId: userId,
                startTime: Date(),
                endTime: Date(),
                attemptCount: 1,
                cacheHit: true
            )

            return cached.response
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localSuggestions = fetchMeetingSuggestions(for: conversationId) {
            if localSuggestions.isValid {
                #if DEBUG
                print("[MeetingSuggestionsService] Returning local meeting suggestions for conversation \(conversationId)")
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
                    conversationId: conversationId,
                    durationMinutes: localSuggestions.durationMinutes,
                    participantCount: localSuggestions.participantCount,
                    generatedAt: localSuggestions.generatedAt,
                    expiresAt: localSuggestions.expiresAt
                )
                // Update memory cache
                cache.set(conversationId, value: CachedMeetingSuggestions(
                    response: response,
                    cachedAt: Date()
                ))
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
            let response: MeetingSuggestionsResponse = try await functionClient.call(
                "suggestMeetingTimes",
                payload: payload,
                userId: userId
            )

            // Update memory cache
            cache.set(conversationId, value: CachedMeetingSuggestions(
                response: response,
                cachedAt: Date()
            ))

            // Update state
            state.set(conversationId, response)

            // Save to local storage
            do {
                try saveMeetingSuggestions(conversationId: conversationId, response: response)
            } catch {
                // Log error but don't fail the entire operation
                #if DEBUG
                print("[MeetingSuggestionsService] Failed to save meeting suggestions locally: \(error)")
                #endif
            }

            return response
        } catch {
            state.setError(conversationId, error.localizedDescription)
            throw error
        }
    }

    /// Track meeting suggestion interaction analytics
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - action: The action taken (e.g., "copy", "share", "dismiss", "accept")
    ///   - suggestionIndex: The index of the suggestion interacted with (0-based)
    ///   - suggestionScore: The score of the suggestion
    func trackInteraction(
        conversationId: String,
        action: String,
        suggestionIndex: Int,
        suggestionScore: Double
    ) async {
        guard let firestoreService = firestoreService else {
            #if DEBUG
            print("[MeetingSuggestionsService] Cannot track analytics - FirestoreService not configured")
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
            print("[MeetingSuggestionsService] Tracked interaction: \(action) for conversation \(conversationId)")
            #endif
        } catch {
            #if DEBUG
            print("[MeetingSuggestionsService] Failed to track analytics (non-fatal): \(error.localizedDescription)")
            #endif
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

    /// Save meeting suggestions to local SwiftData storage
    private func saveMeetingSuggestions(conversationId: String, response: MeetingSuggestionsResponse) throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        // Check if suggestions already exist for this conversation
        let descriptor = FetchDescriptor<MeetingSuggestionEntity>(
            predicate: #Predicate { $0.conversationId == conversationId }
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
                conversationId: conversationId,
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
    private func fetchMeetingSuggestions(for conversationId: String) -> MeetingSuggestionEntity? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<MeetingSuggestionEntity>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Delete meeting suggestions for a conversation from local storage
    private func deleteMeetingSuggestions(for conversationId: String) throws {
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
    func clearExpiredSuggestions() throws {
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
            print("[MeetingSuggestionsService] Cleared \(deletedCount) expired meeting suggestions")
            #endif
        }
    }
}

// MARK: - Cache Model

/// Cached meeting suggestions entry with expiration
struct CachedMeetingSuggestions: Cacheable {
    let response: MeetingSuggestionsResponse
    let cachedAt: Date

    var isExpired: Bool {
        // Use expiry from response
        Date() > response.expiresAt
    }
}
