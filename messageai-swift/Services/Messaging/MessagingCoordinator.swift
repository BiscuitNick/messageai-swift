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
        notificationService: NotificationService? = nil,
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

    /// Ensure bot conversation exists (legacy Dash Bot)
    func ensureBotConversation() async throws -> String {
        // Use legacy method from MessagingService for the special "bot-{userId}" conversation
        // This maintains backward compatibility with existing bot conversations
        guard let currentUserId = currentUserId else {
            throw MessagingError.notAuthenticated
        }
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let botUserId = "dash-bot"
        let now = Date()
        let botRef = db.collection("users").document(botUserId)

        try await botRef.setData([
            "email": "bot@messageai.app",
            "displayName": "Dash Bot",
            "profilePictureURL": "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
            "isOnline": true,
            "lastSeen": Timestamp(date: now),
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)

        let conversationId = "bot-\(currentUserId)"
        let conversationRef = db.collection("conversations").document(conversationId)
        var conversationDoc = try await conversationRef.getDocument()

        let welcomeText = "Hey there! I'm Dash Bot, your quick and helpful assistant. Need help with questions, drafting messages, recommendations, or just a good conversation? I'm here for it. What can I do for you?"
        let participantIds = [currentUserId, botUserId]
        let unreadCount = [currentUserId: 0, botUserId: 0]

        if !conversationDoc.exists {
            try await conversationRef.setData([
                "participantIds": participantIds,
                "isGroup": false,
                "adminIds": [currentUserId],
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "lastMessage": welcomeText,
                "lastMessageTimestamp": Timestamp(date: now),
                "lastSenderId": botUserId,
                "unreadCount": unreadCount,
                "lastInteractionByUser": [
                    currentUserId: Timestamp(date: now),
                    botUserId: Timestamp(date: now)
                ]
            ])

            let messageRef = conversationRef.collection("messages").document("bot-intro")
            try await messageRef.setData([
                "conversationId": conversationId,
                "senderId": botUserId,
                "text": welcomeText,
                "timestamp": Timestamp(date: now),
                "deliveryState": MessageDeliveryState.delivered.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ])

            conversationDoc = try await conversationRef.getDocument()
        }

        let conversationData = conversationDoc.data() ?? [:]
        let lastMessage = conversationData["lastMessage"] as? String ?? welcomeText
        let lastMessageTimestamp = (conversationData["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? now
        let lastSenderId = conversationData["lastSenderId"] as? String
        let unread = conversationData["unreadCount"] as? [String: Int] ?? unreadCount
        let createdAt = (conversationData["createdAt"] as? Timestamp)?.dateValue() ?? now
        let updatedAt = (conversationData["updatedAt"] as? Timestamp)?.dateValue() ?? now
        var lastInteractionByUser = parseTimestampDictionary(conversationData["lastInteractionByUser"])
        if lastInteractionByUser[currentUserId] == nil {
            lastInteractionByUser[currentUserId] = now
        }
        if lastInteractionByUser[botUserId] == nil {
            lastInteractionByUser[botUserId] = now
        }

        try conversationManager.upsertLocalUser(
            id: botUserId,
            email: "bot@messageai.app",
            displayName: "Dash Bot",
            profilePictureURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
            isOnline: true,
            lastSeen: now,
            createdAt: createdAt
        )

        try conversationManager.upsertLocalConversation(
            id: conversationId,
            participantIds: participantIds,
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [currentUserId],
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            lastSenderId: lastSenderId,
            unreadCount: unread,
            lastInteractionByUser: lastInteractionByUser,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let messageRef = conversationRef.collection("messages").document("bot-intro")
        var messageDoc = try await messageRef.getDocument()
        if !messageDoc.exists {
            try await messageRef.setData([
                "conversationId": conversationId,
                "senderId": botUserId,
                "text": welcomeText,
                "timestamp": Timestamp(date: now),
                "deliveryState": MessageDeliveryState.delivered.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            messageDoc = try await messageRef.getDocument()
        }

        // Ensure message listener is active
        firestoreSyncService.observeMessages(for: conversationId)

        return conversationId
    }

    /// Seed mock data for testing (legacy method)
    func seedMockData() async throws {
        guard let currentUserId = currentUserId else {
            throw MessagingError.notAuthenticated
        }

        let now = Date()
        let sampleUsers: [(id: String, name: String, email: String)] = [
            ("mock-alex", "Alex Rivera", "alex@example.com"),
            ("mock-priya", "Priya Patel", "priya@example.com"),
            ("mock-sam", "Sam Carter", "sam@example.com")
        ]

        for sample in sampleUsers {
            let userRef = db.collection("users").document(sample.id)
            try await userRef.setData([
                "email": sample.email,
                "displayName": sample.name,
                "isOnline": Bool.random(),
                "lastSeen": Timestamp(date: now),
                "updatedAt": FieldValue.serverTimestamp(),
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)

            try conversationManager.upsertLocalUser(
                id: sample.id,
                email: sample.email,
                displayName: sample.name,
                profilePictureURL: nil,
                isOnline: true,
                lastSeen: now,
                createdAt: now
            )
        }

        guard let primarySample = sampleUsers.first else { return }

        let demoConversationId = "demo-\(currentUserId)"
        let demoConversationRef = db.collection("conversations").document(demoConversationId)
        var demoConversationDoc = try await demoConversationRef.getDocument()

        let demoMessageText = "Hey there! Ready to build something great today?"
        let demoParticipantIds = [currentUserId, primarySample.id]
        let demoUnread = [currentUserId: 1, primarySample.id: 0]

        if !demoConversationDoc.exists {
            try await demoConversationRef.setData([
                "participantIds": demoParticipantIds,
                "isGroup": false,
                "adminIds": [currentUserId],
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "lastMessage": demoMessageText,
                "lastMessageTimestamp": Timestamp(date: now),
                "lastSenderId": primarySample.id,
                "unreadCount": demoUnread,
                "lastInteractionByUser": [
                    currentUserId: Timestamp(date: now),
                    primarySample.id: Timestamp(date: now)
                ]
            ])

            let messageRef = demoConversationRef.collection("messages").document("demo-intro")
            try await messageRef.setData([
                "conversationId": demoConversationId,
                "senderId": primarySample.id,
                "text": demoMessageText,
                "timestamp": Timestamp(date: now),
                "deliveryState": MessageDeliveryState.delivered.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ])

            demoConversationDoc = try await demoConversationRef.getDocument()
        }

        // Cache conversation to local
        let demoData = demoConversationDoc.data() ?? [:]
        let demoLastMessage = demoData["lastMessage"] as? String ?? demoMessageText
        let demoLastTimestamp = (demoData["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? now
        let demoLastSenderId = demoData["lastSenderId"] as? String
        let demoUnreadCount = demoData["unreadCount"] as? [String: Int] ?? demoUnread
        let demoCreatedAt = (demoData["createdAt"] as? Timestamp)?.dateValue() ?? now
        let demoUpdatedAt = (demoData["updatedAt"] as? Timestamp)?.dateValue() ?? now
        var demoLastInteractionByUser = parseTimestampDictionary(demoData["lastInteractionByUser"])
        if demoLastInteractionByUser[currentUserId] == nil {
            demoLastInteractionByUser[currentUserId] = now
        }
        if demoLastInteractionByUser[primarySample.id] == nil {
            demoLastInteractionByUser[primarySample.id] = now
        }

        try conversationManager.upsertLocalConversation(
            id: demoConversationId,
            participantIds: demoParticipantIds,
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [currentUserId],
            lastMessage: demoLastMessage,
            lastMessageTimestamp: demoLastTimestamp,
            lastSenderId: demoLastSenderId,
            unreadCount: demoUnreadCount,
            lastInteractionByUser: demoLastInteractionByUser,
            createdAt: demoCreatedAt,
            updatedAt: demoUpdatedAt
        )

        firestoreSyncService.observeMessages(for: demoConversationId)
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
