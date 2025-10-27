//
//  AIFeaturesCoordinator.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Centralized coordinator for orchestrating AI feature services
/// This replaces the monolithic AIFeaturesService with a composition of focused services
@MainActor
@Observable
final class AIFeaturesCoordinator {

    // MARK: - Feature Services

    /// Thread summarization service
    let summaryService: SummaryService

    /// Action item extraction service
    let actionItemsService: ActionItemsService

    /// Semantic search service
    let searchService: SearchService

    /// Meeting suggestions service
    let meetingSuggestionsService: MeetingSuggestionsService

    /// Scheduling intent detection service
    let schedulingService: SchedulingService

    /// Decision tracking service
    let decisionTrackingService: DecisionTrackingService

    /// Coordination insights service
    let coordinationInsightsService: CoordinationInsightsService

    // MARK: - Shared Infrastructure

    private let telemetryLogger: TelemetryLogger
    private let functionClient: FirebaseFunctionClient

    // MARK: - Dependencies

    @ObservationIgnored
    private var modelContext: ModelContext?

    @ObservationIgnored
    private var authService: AuthCoordinator?

    @ObservationIgnored
    private var messagingService: MessagingCoordinator?

    @ObservationIgnored
    private var firestoreService: FirestoreCoordinator?

    @ObservationIgnored
    private var networkMonitor: NetworkMonitor?

    // MARK: - Public State

    /// Global processing indicator (aggregated from services)
    var isProcessing: Bool {
        searchService.isLoading ||
        decisionTrackingService.isProcessing ||
        coordinationInsightsService.isProcessing
    }

    /// Global error message (aggregated from services)
    var errorMessage: String? {
        searchService.errorMessage ??
        decisionTrackingService.errorMessage ??
        coordinationInsightsService.errorMessage
    }

    // MARK: - Initialization

    init() {
        // Initialize shared infrastructure
        self.telemetryLogger = TelemetryLogger()
        self.functionClient = FirebaseFunctionClient(telemetryLogger: telemetryLogger)

        // Initialize feature services with shared infrastructure
        self.summaryService = SummaryService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )

        self.actionItemsService = ActionItemsService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )

        self.searchService = SearchService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )

        self.meetingSuggestionsService = MeetingSuggestionsService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )

        self.schedulingService = SchedulingService()

        self.decisionTrackingService = DecisionTrackingService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )

        self.coordinationInsightsService = CoordinationInsightsService(
            functionClient: functionClient,
            telemetryLogger: telemetryLogger
        )
    }

    // MARK: - Configuration

    /// Configure the coordinator with required dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData model context for local persistence
    ///   - authService: Authentication service for user lifecycle
    ///   - messagingService: Messaging service for message mutation observation
    ///   - firestoreService: Firestore service for database operations
    ///   - networkMonitor: Network monitor for connectivity awareness
    func configure(
        modelContext: ModelContext,
        authService: AuthCoordinator,
        messagingService: MessagingCoordinator,
        firestoreCoordinator: FirestoreCoordinator,
        networkMonitor: NetworkMonitor
    ) {
        self.modelContext = modelContext
        self.authService = authService
        self.messagingService = messagingService
        self.firestoreService = firestoreCoordinator
        self.networkMonitor = networkMonitor

        // Configure individual services
        summaryService.configure(
            authService: authService,
            modelContext: modelContext
        )

        actionItemsService.configure(
            authService: authService,
            modelContext: modelContext
        )

        searchService.configure(
            authService: authService,
            modelContext: modelContext
        )

        meetingSuggestionsService.configure(
            authService: authService,
            modelContext: modelContext,
            firestoreService: firestoreCoordinator
        )

        schedulingService.configure(
            modelContext: modelContext,
            meetingSuggestionsService: meetingSuggestionsService,
            networkMonitor: networkMonitor
        )

        decisionTrackingService.configure(
            authService: authService,
            modelContext: modelContext,
            firestoreService: firestoreCoordinator
        )

        coordinationInsightsService.configure(
            authService: authService,
            modelContext: modelContext,
            networkMonitor: networkMonitor
        )
    }

    // MARK: - Cache Management

    /// Clear all in-memory caches across all services
    func clearCaches() {
        summaryService.clearCache()
        actionItemsService.clearCache()
        searchService.clearCache()
        meetingSuggestionsService.clearCache()
        schedulingService.reset()
    }

    /// Clear expired cached data from SwiftData
    /// This is a non-destructive cleanup that only removes stale data
    func clearExpiredCachedData() {
        do {
            try summaryService.clearExpiredSummaries()
            try searchService.clearExpiredResults()
            try meetingSuggestionsService.clearExpiredSuggestions()
            try schedulingService.clearExpiredSnoozes()
            try coordinationInsightsService.clearExpiredInsights()
            try coordinationInsightsService.clearExpiredAlerts()
            #if DEBUG
            print("[AIFeaturesCoordinator] Periodic cleanup of expired cached data completed")
            #endif
        } catch {
            #if DEBUG
            print("[AIFeaturesCoordinator] Error during periodic cleanup: \(error.localizedDescription)")
            #endif
        }
    }

    /// Reset all services (called on sign-out)
    func reset() {
        clearCaches()
        decisionTrackingService.reset()
        coordinationInsightsService.reset()
    }

    // MARK: - Lifecycle Hooks

    /// Called when user signs in
    func onSignIn() {
        // Refresh coordination insights on sign-in
        Task { @MainActor [weak self] in
            await self?.coordinationInsightsService.refreshInsights()
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
        print("[AIFeaturesCoordinator] Message mutation: conversation=\(conversationId), message=\(messageId)")
        #endif

        // Detect scheduling intent and auto-prefetch meeting suggestions
        Task { @MainActor [weak self] in
            await self?.schedulingService.onMessageMutation(
                conversationId: conversationId,
                messageId: messageId
            )
        }

        // Future implementations will trigger other AI analysis here:
        // - Check for action items
        // - Update priority scores
        // - Track decisions
    }

    /// Process pending scheduling suggestion requests when network returns
    /// Should be called when network connectivity is restored
    func processPendingSchedulingSuggestions() async {
        await schedulingService.processPendingSuggestions()
    }

    // MARK: - Background Refresh

    /// Refresh coordination insights from Firestore and clean up expired data
    /// Call this on app foreground or when network connectivity returns
    /// - Parameter forceAnalysis: If true, triggers new analysis via Cloud Function before syncing
    func refreshCoordinationInsights(forceAnalysis: Bool = false) async {
        await coordinationInsightsService.refreshInsights(forceAnalysis: forceAnalysis)
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
        print("[AIFeaturesCoordinator] Submitted AI feedback: \(feedback.featureType) for conversation \(feedback.conversationId)")
        #endif
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
            return "AIFeaturesCoordinator not properly configured"
        case .unauthorized:
            return "User not authorized for AI features"
        }
    }
}
