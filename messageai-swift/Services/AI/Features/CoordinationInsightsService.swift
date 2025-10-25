//
//  CoordinationInsightsService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for coordination insights and proactive alerts
@MainActor
@Observable
final class CoordinationInsightsService {

    // MARK: - Public State

    /// Global processing state
    var isProcessing = false

    /// Global error message
    var errorMessage: String?

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private let firestore = Firestore.firestore()
    private weak var authService: AuthService?
    private weak var modelContext: ModelContext?
    private weak var networkMonitor: NetworkMonitor?

    // MARK: - Initialization

    init(
        functionClient: FirebaseFunctionClient,
        telemetryLogger: TelemetryLogger
    ) {
        self.functionClient = functionClient
        self.telemetryLogger = telemetryLogger
    }

    // MARK: - Configuration

    func configure(
        authService: AuthService,
        modelContext: ModelContext,
        networkMonitor: NetworkMonitor
    ) {
        self.authService = authService
        self.modelContext = modelContext
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public API

    /// Sync coordination insights from Firestore to local SwiftData storage
    func syncInsights() async throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        guard Auth.auth().currentUser != nil else {
            throw AIFeaturesError.unauthorized
        }

        #if DEBUG
        print("[CoordinationInsightsService] Starting coordination insights sync")
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
                print("[CoordinationInsightsService] Skipping malformed insight document: \(document.documentID)")
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
        print("[CoordinationInsightsService] Coordination insights sync complete: \(syncedCount) synced, \(dedupedCount) deduplicated")
        #endif
    }

    /// Trigger coordination analysis via Cloud Function
    func triggerAnalysis() async throws -> CoordinationAnalysisResult {
        guard let userId = authService?.currentUser?.id else {
            throw AIFeaturesError.unauthorized
        }

        #if DEBUG
        print("[CoordinationInsightsService] Triggering coordination analysis via Cloud Function")
        #endif

        let response: CoordinationAnalysisResult = try await functionClient.call(
            "triggerCoordinationAnalysis",
            userId: userId
        )

        #if DEBUG
        print("[CoordinationInsightsService] Analysis complete: \(response.conversationsAnalyzed) conversations, \(response.insightsGenerated) insights")
        #endif

        return response
    }

    /// Refresh coordination insights from Firestore and clean up expired data
    /// When forceAnalysis is true, triggers Cloud Function to regenerate insights
    func refreshInsights(forceAnalysis: Bool = false) async {
        guard let networkMonitor = networkMonitor, networkMonitor.isConnected else {
            #if DEBUG
            print("[CoordinationInsightsService] Network offline - skipping refresh")
            #endif
            return
        }

        guard authService?.currentUser != nil else {
            #if DEBUG
            print("[CoordinationInsightsService] No user logged in - skipping refresh")
            #endif
            return
        }

        #if DEBUG
        print("[CoordinationInsightsService] Refreshing insights (forceAnalysis: \(forceAnalysis))")
        #endif

        do {
            // If forceAnalysis, trigger new analysis via Cloud Function first
            if forceAnalysis {
                let result = try await triggerAnalysis()
                #if DEBUG
                print("[CoordinationInsightsService] Triggered analysis: \(result.insightsGenerated) insights generated")
                #endif
            }

            // Sync latest insights from Firestore (includes newly generated ones)
            try await syncInsights()

            // Clean up expired data
            try clearExpiredInsights()
            try clearExpiredAlerts()

            #if DEBUG
            print("[CoordinationInsightsService] Refresh complete")
            #endif
        } catch {
            #if DEBUG
            print("[CoordinationInsightsService] Failed to refresh: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to refresh coordination insights: \(error.localizedDescription)"
        }
    }

    /// Fetch coordination insights for a conversation from local SwiftData
    func fetchInsights(for conversationId: String) -> CoordinationInsightEntity? {
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
    func fetchAllInsights() -> [CoordinationInsightEntity] {
        guard let modelContext = modelContext else { return [] }

        let descriptor = FetchDescriptor<CoordinationInsightEntity>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )

        let allInsights = (try? modelContext.fetch(descriptor)) ?? []
        return allInsights.filter { !$0.isExpired }
    }

    /// Fetch active proactive alerts from local SwiftData
    func fetchAlerts(for conversationId: String? = nil) -> [ProactiveAlertEntity] {
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

    /// Clear expired coordination insights from local storage
    func clearExpiredInsights() throws {
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
            print("[CoordinationInsightsService] Cleared \(deletedCount) expired insights")
            #endif
        }
    }

    /// Clear expired proactive alerts from local storage
    func clearExpiredAlerts() throws {
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
            print("[CoordinationInsightsService] Cleared \(deletedCount) expired alerts")
            #endif
        }
    }

    /// Reset service state
    func reset() {
        isProcessing = false
        errorMessage = nil
    }

    // MARK: - Private Helpers

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

        // Parse nested arrays (from original AIFeaturesService)
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

    // MARK: - Parsing Helpers (from original AIFeaturesService)

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
