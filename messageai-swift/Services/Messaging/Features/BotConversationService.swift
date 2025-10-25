//
//  BotConversationService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for bot conversation management
@MainActor
final class BotConversationService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var currentUserId: String?

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(modelContext: ModelContext, currentUserId: String) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
    }

    // MARK: - Public API

    /// Create or get existing conversation with a bot
    /// - Parameter botId: The bot ID (without "bot:" prefix)
    /// - Returns: Conversation ID
    /// - Throws: MessagingError
    func createConversationWithBot(botId: String) async throws -> String {
        guard let currentUserId = currentUserId else {
            throw MessagingError.notAuthenticated
        }
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let botParticipantId = "bot:\(botId)"
        let participantSet = Set([currentUserId, botParticipantId])

        // Check for existing local conversation
        let localDescriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.participantIds.contains(botParticipantId) &&
                conversation.participantIds.contains(currentUserId) &&
                conversation.isGroup == false
            }
        )

        if let existing = try modelContext.fetch(localDescriptor).first {
            #if DEBUG
            print("[BotConversationService] Found existing bot conversation: \(existing.id)")
            #endif
            return existing.id
        }

        // Check Firestore for existing conversation
        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .getDocuments()

        for document in snapshot.documents {
            let data = document.data()
            let participants = SwiftDataHelper.stringArray(from: data["participants"])
            let isGroup = data["isGroup"] as? Bool ?? false

            if !isGroup && Set(participants) == participantSet {
                #if DEBUG
                print("[BotConversationService] Found existing remote bot conversation: \(document.documentID)")
                #endif
                // Cache to local
                try await cacheConversation(id: document.documentID, data: data)
                return document.documentID
            }
        }

        // Create new bot conversation
        let conversationId = UUID().uuidString
        let timestamp = Timestamp(date: Date())
        let welcomeText = welcomeMessage(for: botId)

        let conversationData: [String: Any] = [
            "participants": Array(participantSet),
            "isGroup": false,
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "lastMessage": welcomeText,
            "lastMessageTimestamp": timestamp,
            "lastMessageSenderId": botParticipantId,
            "unreadCount": [currentUserId: 1] // Bot's welcome message is unread
        ]

        // Create conversation in Firestore
        try await db.collection("conversations").document(conversationId).setData(conversationData)

        // Send welcome message from bot
        try await sendBotWelcomeMessage(
            conversationId: conversationId,
            botId: botId,
            welcomeText: welcomeText
        )

        // Cache to local
        try await cacheConversation(id: conversationId, data: conversationData)

        #if DEBUG
        print("[BotConversationService] Created new bot conversation: \(conversationId)")
        #endif

        return conversationId
    }

    /// Send a message as a bot
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - text: Message text
    ///   - botUserId: Bot user ID (with "bot:" prefix)
    /// - Throws: MessagingError or Firestore errors
    func sendMessageAsBot(conversationId: String, text: String, botUserId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw MessagingError.notAuthenticated
        }

        let messageId = UUID().uuidString
        let timestamp = Timestamp(date: Date())

        let messageData: [String: Any] = [
            "senderId": botUserId,
            "text": text,
            "timestamp": timestamp,
            "deliveryState": MessageDeliveryState.sent.rawValue,
            "conversationId": conversationId
        ]

        // Create message in Firestore
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .setData(messageData)

        // Update conversation's last message
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "lastMessage": text,
                "lastMessageTimestamp": timestamp,
                "lastMessageSenderId": botUserId,
                "updatedAt": timestamp
            ])

        #if DEBUG
        print("[BotConversationService] Sent bot message in conversation \(conversationId)")
        #endif
    }

    /// Ensure a specific bot conversation exists, create if needed
    /// - Returns: Conversation ID
    /// - Throws: MessagingError
    func ensureBotConversation() async throws -> String {
        return try await createConversationWithBot(botId: "dash-bot")
    }

    // MARK: - Private Helpers

    /// Send welcome message from bot
    private func sendBotWelcomeMessage(
        conversationId: String,
        botId: String,
        welcomeText: String
    ) async throws {
        let messageId = UUID().uuidString
        let timestamp = Timestamp(date: Date())
        let botParticipantId = "bot:\(botId)"

        let messageData: [String: Any] = [
            "senderId": botParticipantId,
            "text": welcomeText,
            "timestamp": timestamp,
            "deliveryState": MessageDeliveryState.sent.rawValue,
            "conversationId": conversationId
        ]

        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .setData(messageData)
    }

    /// Cache conversation to local SwiftData
    private func cacheConversation(id: String, data: [String: Any]) async throws {
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let participants = SwiftDataHelper.stringArray(from: data["participants"])
        let isGroup = data["isGroup"] as? Bool ?? false
        let groupName = data["groupName"] as? String
        let createdAt = SwiftDataHelper.parseTimestamp(data["createdAt"])
        let updatedAt = SwiftDataHelper.parseTimestamp(data["updatedAt"])
        let lastMessage = data["lastMessage"] as? String ?? ""
        let lastMessageTimestamp = SwiftDataHelper.parseTimestamp(data["lastMessageTimestamp"])
        let lastMessageSenderId = data["lastMessageSenderId"] as? String ?? ""
        let unreadCount = SwiftDataHelper.parseUnreadCount(data["unreadCount"], participants: participants)

        let conversation = ConversationEntity(
            id: id,
            participantIds: participants,
            isGroup: isGroup,
            groupName: groupName,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            lastSenderId: lastMessageSenderId,
            unreadCount: unreadCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        modelContext.insert(conversation)
        try modelContext.save()
    }

    /// Get welcome message for a bot
    private func welcomeMessage(for botId: String) -> String {
        switch botId {
        case "dash-bot":
            return "👋 Hi! I'm Dash, your AI assistant. How can I help you today?"
        default:
            return "👋 Hello! I'm here to assist you."
        }
    }
}
