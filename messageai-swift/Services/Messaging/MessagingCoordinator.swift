//
//  MessagingCoordinator.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import Observation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Coordinator that composes all messaging services
@MainActor
@Observable
final class MessagingCoordinator {

    // MARK: - Debug

    struct DebugSnapshot {
        let isConfigured: Bool
        let currentUserId: String?
        let activeListeners: Int
    }

    var debugSnapshot: DebugSnapshot {
        DebugSnapshot(
            isConfigured: modelContext != nil && currentUserId != nil,
            currentUserId: currentUserId,
            activeListeners: listenerManager.activeCount
        )
    }

    // MARK: - Services

    let conversationManager: ConversationManagementService
    let messageSendingService: MessageSendingService
    let firestoreSyncService: FirestoreSyncService
    let readStatusService: ReadStatusService
    let botConversationService: BotConversationService

    // Shared Infrastructure
    let listenerManager: FirestoreListenerManager
    let deliveryStateTracker: DeliveryStateTracker

    // MARK: - Properties

    private weak var modelContext: ModelContext?
    private var currentUserId: String?
    private let db: Firestore

    // AI Features Callback
    var onMessageMutation: ((String, String) -> Void)? {
        didSet {
            messageSendingService.onMessageMutation = onMessageMutation
            firestoreSyncService.onMessageMutation = onMessageMutation
        }
    }

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db

        // Initialize shared infrastructure
        self.listenerManager = FirestoreListenerManager()
        self.deliveryStateTracker = DeliveryStateTracker()

        // Initialize services
        self.conversationManager = ConversationManagementService(db: db)
        self.messageSendingService = MessageSendingService(db: db)
        self.firestoreSyncService = FirestoreSyncService(db: db)
        self.readStatusService = ReadStatusService(db: db)
        self.botConversationService = BotConversationService(db: db)
    }

    // MARK: - Configuration

    func configure(
        modelContext: ModelContext,
        currentUserId: String,
        notificationService: NotificationCoordinator? = nil,
        networkSimulator: NetworkSimulator? = nil
    ) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId

        // Configure shared infrastructure
        deliveryStateTracker.configure(modelContext: modelContext)

        // Configure services
        conversationManager.configure(
            modelContext: modelContext,
            currentUserId: currentUserId
        )

        messageSendingService.configure(
            modelContext: modelContext,
            currentUserId: currentUserId,
            deliveryStateTracker: deliveryStateTracker,
            conversationManager: conversationManager,
            networkSimulator: networkSimulator
        )

        firestoreSyncService.configure(
            modelContext: modelContext,
            currentUserId: currentUserId,
            listenerManager: listenerManager,
            conversationManager: conversationManager,
            notificationService: notificationService
        )

        readStatusService.configure(
            modelContext: modelContext,
            currentUserId: currentUserId
        )

        botConversationService.configure(
            modelContext: modelContext,
            currentUserId: currentUserId
        )

        #if DEBUG
        print("[MessagingCoordinator] Configured for user: \(currentUserId)")
        #endif
    }

    func setAppInForeground(_ isInForeground: Bool) {
        firestoreSyncService.setAppInForeground(isInForeground)
    }

    func reset() {
        firestoreSyncService.reset()
        currentUserId = nil
        onMessageMutation = nil

        #if DEBUG
        print("[MessagingCoordinator] Reset")
        #endif
    }

    // MARK: - Conversation Management

    /// Create a new conversation or return existing one
    func createConversation(
        with participants: [String],
        isGroup: Bool = false,
        groupName: String? = nil
    ) async throws -> String {
        let conversationId = try await conversationManager.createConversation(
            with: participants,
            isGroup: isGroup,
            groupName: groupName
        )

        // Start observing messages for this conversation
        firestoreSyncService.observeMessages(for: conversationId)

        return conversationId
    }

    /// Create or get conversation with a bot
    func createConversationWithBot(botId: String) async throws -> String {
        let conversationId = try await botConversationService.createConversationWithBot(
            botId: botId
        )

        // Start observing messages for this conversation
        firestoreSyncService.observeMessages(for: conversationId)

        return conversationId
    }

    // MARK: - Message Sending

    /// Send a message in a conversation
    func sendMessage(conversationId: String, text: String) async throws {
        try await messageSendingService.sendMessage(
            conversationId: conversationId,
            text: text
        )
    }

    /// Send a message as a bot
    func sendMessageAsBot(conversationId: String, text: String, botUserId: String) async throws {
        try await botConversationService.sendMessageAsBot(
            conversationId: conversationId,
            text: text,
            botUserId: botUserId
        )
    }

    /// Retry a failed message
    func retryFailedMessage(messageId: String) async throws {
        try await messageSendingService.retryFailedMessage(messageId: messageId)
    }

    // MARK: - Read Status

    /// Mark a conversation as read
    func markConversationAsRead(_ conversationId: String) async {
        await readStatusService.markConversationAsRead(conversationId)
    }

    /// Mark all messages in a conversation as read
    func markConversationMessagesAsRead(conversationId: String) async throws {
        try await readStatusService.markConversationMessagesAsRead(
            conversationId: conversationId
        )
    }

    // MARK: - Sync Management

    /// Ensure message listener is active for a conversation
    func ensureMessageListener(for conversationId: String) {
        firestoreSyncService.ensureMessageListener(for: conversationId)
    }

    // MARK: - Private Helpers

    private func parseTimestampDictionary(_ value: Any?) -> [String: Date] {
        guard let map = value as? [String: Any] else { return [:] }
        var result: [String: Date] = [:]

        for (userId, raw) in map {
            if let timestamp = raw as? Timestamp {
                result[userId] = timestamp.dateValue()
            } else if let date = raw as? Date {
                result[userId] = date
            }
        }

        return result
    }
}
