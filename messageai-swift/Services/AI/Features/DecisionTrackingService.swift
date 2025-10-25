//
//  DecisionTrackingService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Service responsible for decision tracking features
@MainActor
@Observable
final class DecisionTrackingService {

    // MARK: - Public State

    /// Global processing state
    var isProcessing = false

    /// Global error message
    var errorMessage: String?

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private weak var authService: AuthService?
    private weak var modelContext: ModelContext?
    private weak var firestoreService: FirestoreCoordinator?

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
        firestoreService: FirestoreCoordinator
    ) {
        self.authService = authService
        self.modelContext = modelContext
        self.firestoreService = firestoreService
    }

    // MARK: - Public API

    /// Track decisions in a conversation
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
        guard let userId = authService?.currentUser?.id else {
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
            let response: TrackedDecisionsResponse = try await functionClient.call(
                "recordDecisions",
                payload: payload,
                userId: userId
            )

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

    /// Reset service state
    func reset() {
        isProcessing = false
        errorMessage = nil
    }
}
