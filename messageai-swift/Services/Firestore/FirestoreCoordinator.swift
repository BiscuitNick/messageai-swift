//
//  FirestoreCoordinator.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import Observation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions

/// Coordinator that composes all Firestore services
@MainActor
@Observable
final class FirestoreCoordinator {

    // MARK: - Services

    let userPresenceService: UserPresenceService
    let userSyncService: UserSyncService
    let botSyncService: BotSyncService
    let actionItemsService: ActionItemsSyncService
    let decisionsService: DecisionsSyncService
    let botAgentService: BotAgentService

    // Shared Infrastructure
    private let listenerManager: FirestoreListenerManager

    // MARK: - Properties

    private let db: Firestore
    private let functions: Functions

    /// Internal accessor for Firestore database (for use by other services)
    var firestore: Firestore {
        db
    }

    // MARK: - Initialization

    init() {
        let firestore = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        firestore.settings = settings
        self.db = firestore
        self.functions = Functions.functions(region: "us-central1")

        // Initialize shared infrastructure
        self.listenerManager = FirestoreListenerManager()

        // Initialize services
        self.userPresenceService = UserPresenceService(db: firestore)
        self.userSyncService = UserSyncService(db: firestore)
        self.botSyncService = BotSyncService(db: firestore)
        self.actionItemsService = ActionItemsSyncService(db: firestore)
        self.decisionsService = DecisionsSyncService(db: firestore)
        self.botAgentService = BotAgentService(functions: functions)

        // Configure services with shared infrastructure
        userSyncService.configure(listenerManager: listenerManager)
        botSyncService.configure(listenerManager: listenerManager)
        actionItemsService.configure(listenerManager: listenerManager)
        decisionsService.configure(listenerManager: listenerManager)
    }

    // MARK: - User Presence

    /// Upsert a user to Firestore
    func upsertUser(_ user: AuthCoordinator.AppUser) async throws {
        try await userPresenceService.upsertUser(user)
    }

    /// Update user presence status
    func updatePresence(userId: String, isOnline: Bool, lastSeen: Date = Date()) async throws {
        try await userPresenceService.updatePresence(
            userId: userId,
            isOnline: isOnline,
            lastSeen: lastSeen
        )
    }

    /// Update user profile photo
    func updateUserProfilePhoto(userId: String, photoURL: URL) async throws {
        try await userPresenceService.updateUserProfilePhoto(
            userId: userId,
            photoURL: photoURL
        )
    }

    // MARK: - User Sync

    /// Start observing users collection
    func startUserListener(modelContext: ModelContext) {
        userSyncService.startUserListener(modelContext: modelContext)
    }

    /// Stop observing users collection
    func stopUserListener() {
        userSyncService.stopUserListener()
    }

    // MARK: - Bot Sync

    /// Start observing bots collection
    func startBotListener(modelContext: ModelContext) {
        botSyncService.startBotListener(modelContext: modelContext)
    }

    /// Stop observing bots collection
    func stopBotListener() {
        botSyncService.stopBotListener()
    }

    // MARK: - Action Items

    /// Start observing action items for a conversation
    func startActionItemsListener(conversationId: String, modelContext: ModelContext) {
        actionItemsService.startActionItemsListener(
            conversationId: conversationId,
            modelContext: modelContext
        )
    }

    /// Stop observing action items for a conversation
    func stopActionItemsListener(conversationId: String) {
        actionItemsService.stopActionItemsListener(conversationId: conversationId)
    }

    /// Stop all action items listeners
    func stopAllActionItemsListeners() {
        actionItemsService.stopAllActionItemsListeners()
    }

    /// Create a new action item
    func createActionItem(
        conversationId: String,
        actionItemId: String,
        task: String,
        priority: ActionItemPriority,
        status: ActionItemStatus,
        assignedTo: String?,
        dueDate: Date?
    ) async throws {
        try await actionItemsService.createActionItem(
            conversationId: conversationId,
            actionItemId: actionItemId,
            task: task,
            priority: priority,
            status: status,
            assignedTo: assignedTo,
            dueDate: dueDate
        )
    }

    /// Update an existing action item
    func updateActionItem(
        conversationId: String,
        actionItemId: String,
        task: String,
        priority: ActionItemPriority,
        status: ActionItemStatus,
        assignedTo: String?,
        dueDate: Date?
    ) async throws {
        try await actionItemsService.updateActionItem(
            conversationId: conversationId,
            actionItemId: actionItemId,
            task: task,
            priority: priority,
            status: status,
            assignedTo: assignedTo,
            dueDate: dueDate
        )
    }

    /// Delete an action item
    func deleteActionItem(conversationId: String, actionItemId: String) async throws {
        try await actionItemsService.deleteActionItem(
            conversationId: conversationId,
            actionItemId: actionItemId
        )
    }

    // MARK: - Decisions

    /// Start observing decisions for a conversation
    func startDecisionsListener(conversationId: String, modelContext: ModelContext) {
        decisionsService.startDecisionsListener(
            conversationId: conversationId,
            modelContext: modelContext
        )
    }

    /// Stop observing decisions for a conversation
    func stopDecisionsListener(conversationId: String) {
        decisionsService.stopDecisionsListener(conversationId: conversationId)
    }

    /// Stop all decisions listeners
    func stopAllDecisionsListeners() {
        decisionsService.stopAllDecisionsListeners()
    }

    /// Create a new decision
    func createDecision(
        conversationId: String,
        decisionId: String,
        decisionText: String,
        contextSummary: String,
        participantIds: [String],
        decidedAt: Date,
        followUpStatus: DecisionFollowUpStatus,
        confidenceScore: Double
    ) async throws {
        try await decisionsService.createDecision(
            conversationId: conversationId,
            decisionId: decisionId,
            decisionText: decisionText,
            contextSummary: contextSummary,
            participantIds: participantIds,
            decidedAt: decidedAt,
            followUpStatus: followUpStatus,
            confidenceScore: confidenceScore
        )
    }

    /// Update a decision
    func updateDecision(
        conversationId: String,
        decisionId: String,
        decisionText: String,
        contextSummary: String,
        decidedAt: Date,
        followUpStatus: DecisionFollowUpStatus
    ) async throws {
        try await decisionsService.updateDecision(
            conversationId: conversationId,
            decisionId: decisionId,
            decisionText: decisionText,
            contextSummary: contextSummary,
            decidedAt: decidedAt,
            followUpStatus: followUpStatus
        )
    }

    /// Update a decision's follow-up status
    func updateDecisionStatus(
        conversationId: String,
        decisionId: String,
        followUpStatus: DecisionFollowUpStatus
    ) async throws {
        try await decisionsService.updateDecisionStatus(
            conversationId: conversationId,
            decisionId: decisionId,
            followUpStatus: followUpStatus
        )
    }

    /// Update a decision's reminder date
    func updateDecisionReminder(
        conversationId: String,
        decisionId: String,
        reminderDate: Date?
    ) async throws {
        try await decisionsService.updateDecisionReminder(
            conversationId: conversationId,
            decisionId: decisionId,
            reminderDate: reminderDate
        )
    }

    /// Delete a decision
    func deleteDecision(conversationId: String, decisionId: String) async throws {
        try await decisionsService.deleteDecision(
            conversationId: conversationId,
            decisionId: decisionId
        )
    }

    // MARK: - Bot Agent

    /// Chat with a bot agent
    func chatWithAgent(messages: [BotAgentService.AgentMessage], conversationId: String) async throws {
        try await botAgentService.chatWithAgent(
            messages: messages,
            conversationId: conversationId
        )
    }

    /// Ensure bots exist in Firestore
    func ensureBotExists() async throws {
        try await botAgentService.ensureBotExists()
    }

    /// Delete all bots from Firestore
    func deleteBots() async throws {
        try await botAgentService.deleteBots()
    }
}
