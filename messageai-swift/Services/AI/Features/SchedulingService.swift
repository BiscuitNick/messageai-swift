//
//  SchedulingService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Service responsible for scheduling intent detection and auto-prefetch logic
@MainActor
@Observable
final class SchedulingService {

    // MARK: - Public State

    /// Per-conversation scheduling intent detection state
    var intentDetected: [String: Bool] = [:]

    /// Per-conversation scheduling intent confidence scores
    var intentConfidence: [String: Double] = [:]

    // MARK: - Dependencies

    private weak var modelContext: ModelContext?
    private weak var meetingSuggestionsService: MeetingSuggestionsService?
    private weak var networkMonitor: NetworkMonitor?

    // MARK: - Offline Queue

    /// Pending scheduling suggestion requests to retry when network returns
    private struct PendingSchedulingSuggestion: Hashable {
        let conversationId: String
        let messageId: String
        let timestamp: Date
    }

    private var pendingSchedulingSuggestions: Set<PendingSchedulingSuggestion> = []

    // MARK: - Prefetch Tracking

    /// Track conversations where we've already auto-prefetched meeting suggestions
    private var prefetchedConversations: Set<String> = []

    /// Track last prefetch timestamp per conversation for debouncing
    private var lastPrefetchTimestamps: [String: Date] = [:]

    /// Debounce interval in seconds (default: 5 minutes)
    private let debounceInterval: TimeInterval = 300

    // MARK: - Initialization

    init() {}

    // MARK: - Configuration

    func configure(
        modelContext: ModelContext,
        meetingSuggestionsService: MeetingSuggestionsService,
        networkMonitor: NetworkMonitor
    ) {
        self.modelContext = modelContext
        self.meetingSuggestionsService = meetingSuggestionsService
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public API

    /// Handle message mutation and detect scheduling intent
    /// - Parameters:
    ///   - conversationId: The ID of the conversation
    ///   - messageId: The ID of the message
    func onMessageMutation(conversationId: String, messageId: String) async {
        // Check if suggestions are currently snoozed
        if isSchedulingSuggestionsSnoozed(for: conversationId) {
            #if DEBUG
            print("[SchedulingService] Scheduling suggestions snoozed for conversation \(conversationId)")
            #endif
            return
        }

        // Check debounce: don't prefetch if we recently did
        if let lastPrefetch = lastPrefetchTimestamps[conversationId] {
            let timeSinceLastPrefetch = Date().timeIntervalSince(lastPrefetch)
            if timeSinceLastPrefetch < debounceInterval {
                #if DEBUG
                print("[SchedulingService] Debouncing prefetch for conversation \(conversationId) (last: \(Int(timeSinceLastPrefetch))s ago)")
                #endif
                return
            }
        }

        // Don't prefetch if we've already done it for this conversation
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
        print("[SchedulingService] Scheduling intent detected (confidence: \(confidence)) in conversation \(conversationId)")
        #endif

        // Update observable state for UI
        intentDetected[conversationId] = true
        intentConfidence[conversationId] = confidence

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
            print("[SchedulingService] Skipping prefetch - not enough human participants (\(humanParticipants.count))")
            #endif
            return
        }

        // Check network connectivity before attempting fetch
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[SchedulingService] Network offline - queueing scheduling suggestion for conversation \(conversationId)")
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
        await prefetchMeetingSuggestions(
            conversationId: conversationId,
            participantIds: humanParticipants
        )
    }

    /// Process pending scheduling suggestion requests when network returns
    func processPendingSuggestions() async {
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[SchedulingService] Network still offline - cannot process pending suggestions")
            #endif
            return
        }

        guard !pendingSchedulingSuggestions.isEmpty else {
            return
        }

        #if DEBUG
        print("[SchedulingService] Processing \(pendingSchedulingSuggestions.count) pending scheduling suggestions")
        #endif

        // Process all pending requests
        let pending = Array(pendingSchedulingSuggestions)
        pendingSchedulingSuggestions.removeAll()

        for request in pending {
            // Re-trigger detection for each pending request
            await onMessageMutation(
                conversationId: request.conversationId,
                messageId: request.messageId
            )
        }

        #if DEBUG
        print("[SchedulingService] Finished processing pending scheduling suggestions")
        #endif
    }

    /// Clear all state
    func reset() {
        intentDetected.removeAll()
        intentConfidence.removeAll()
        prefetchedConversations.removeAll()
        lastPrefetchTimestamps.removeAll()
        pendingSchedulingSuggestions.removeAll()
    }

    // MARK: - Snooze Management

    /// Check if scheduling suggestions are snoozed for a conversation
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

    /// Snooze scheduling suggestions for a conversation
    func snoozeSuggestions(for conversationId: String, duration: TimeInterval = 3600) throws {
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
        print("[SchedulingService] Snoozed scheduling suggestions for conversation \(conversationId) until \(snoozedUntil)")
        #endif
    }

    /// Clear snooze state for a conversation
    func clearSnooze(for conversationId: String) throws {
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
            print("[SchedulingService] Cleared snooze for conversation \(conversationId)")
            #endif
        }
    }

    /// Clear all expired snoozes from local storage
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
            print("[SchedulingService] Cleared \(deletedCount) expired snoozes")
            #endif
        }
    }

    // MARK: - Private Helpers

    /// Auto-prefetch meeting suggestions
    private func prefetchMeetingSuggestions(
        conversationId: String,
        participantIds: [String]
    ) async {
        guard let meetingSuggestionsService = meetingSuggestionsService else {
            return
        }

        do {
            #if DEBUG
            print("[SchedulingService] Auto-prefetching meeting suggestions for conversation \(conversationId)")
            #endif

            _ = try await meetingSuggestionsService.suggestMeetingTimes(
                conversationId: conversationId,
                participantIds: participantIds,
                durationMinutes: 60,
                preferredDays: 14,
                forceRefresh: false
            )

            #if DEBUG
            print("[SchedulingService] Successfully prefetched meeting suggestions for conversation \(conversationId)")
            #endif
        } catch {
            #if DEBUG
            print("[SchedulingService] Failed to prefetch meeting suggestions: \(error.localizedDescription)")
            #endif
            // Remove from prefetched set and timestamp so we can retry later
            prefetchedConversations.remove(conversationId)
            lastPrefetchTimestamps.removeValue(forKey: conversationId)

            // If error was network-related, queue for retry
            if let networkMonitor = networkMonitor, !networkMonitor.isConnected {
                let pending = PendingSchedulingSuggestion(
                    conversationId: conversationId,
                    messageId: "", // We don't need messageId for retry
                    timestamp: Date()
                )
                pendingSchedulingSuggestions.insert(pending)
            }
        }
    }
}
