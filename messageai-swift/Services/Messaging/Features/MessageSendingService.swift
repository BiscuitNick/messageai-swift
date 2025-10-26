//
//  MessageSendingService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for sending and retrying messages
@MainActor
final class MessageSendingService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var currentUserId: String?
    private var networkSimulator: NetworkSimulator?

    // Dependencies
    private var deliveryStateTracker: DeliveryStateTracker?
    private var conversationManager: ConversationManagementService?

    // Pending message tasks
    private var pendingMessageTasks: [String: Task<Void, Never>] = [:]

    // Callbacks
    var onMessageMutation: ((String, String) -> Void)?  // (conversationId, messageId)

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(
        modelContext: ModelContext,
        currentUserId: String,
        deliveryStateTracker: DeliveryStateTracker,
        conversationManager: ConversationManagementService,
        networkSimulator: NetworkSimulator? = nil
    ) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
        self.deliveryStateTracker = deliveryStateTracker
        self.conversationManager = conversationManager
        self.networkSimulator = networkSimulator
    }

    // MARK: - Public API

    /// Send a new message in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - text: Message text
    /// - Throws: MessagingError
    func sendMessage(conversationId: String, text: String) async throws {
        guard let currentUserId = currentUserId, let modelContext = modelContext else {
            throw MessagingError.notAuthenticated
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = Date()
        let messageId = UUID().uuidString

        // Create optimistic local message
        let optimisticMessage = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            text: trimmed,
            timestamp: timestamp,
            deliveryState: .pending,
            readReceipts: [:],
            updatedAt: timestamp
        )

        modelContext.insert(optimisticMessage)
        try? modelContext.save()

        #if DEBUG
        print("[MessageSendingService] Created local message with .pending state: \(messageId)")
        #endif

        // Notify AI Features of new message
        onMessageMutation?(conversationId, messageId)

        let conversationRef = db.collection("conversations").document(conversationId)
        let messageRef = conversationRef.collection("messages").document(messageId)

        // Include deliveryState in the payload so it persists across app restarts
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "senderId": currentUserId,
            "text": trimmed,
            "timestamp": Timestamp(date: timestamp),
            "deliveryState": MessageDeliveryState.pending.rawValue, // Write pending state
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let task = Task { [weak self] in
            do {
                #if DEBUG
                print("[MessageSendingService] Starting Firestore write for message: \(messageId)")
                #endif

                // Write to Firestore (completes when written to cache)
                if let simulator = self?.networkSimulator {
                    try await simulator.execute {
                        try await messageRef.setData(payload)
                    }
                } else {
                    try await messageRef.setData(payload)
                }

                #if DEBUG
                print("[MessageSendingService] Firestore write queued successfully")
                #endif

                // FirestoreSyncService will handle state transitions based on cache/server status

                // Get current conversation to update lastInteractionByUser and unreadCount
                let conversationDoc: DocumentSnapshot
                if let simulator = self?.networkSimulator {
                    conversationDoc = try await simulator.execute {
                        try await conversationRef.getDocument()
                    }
                } else {
                    conversationDoc = try await conversationRef.getDocument()
                }

                var lastInteractionByUser = Self.parseTimestampDictionary(
                    conversationDoc.data()?["lastInteractionByUser"]
                )
                lastInteractionByUser[currentUserId] = timestamp

                // Convert to Firestore format
                var firestoreInteractionMap: [String: Any] = [:]
                for (userId, date) in lastInteractionByUser {
                    firestoreInteractionMap[userId] = Timestamp(date: date)
                }

                // Update unread counts for all participants except sender
                let currentUnreadCounts = conversationDoc.data()?["unreadCount"] as? [String: Int] ?? [:]
                var updatedUnreadCounts = currentUnreadCounts

                // Increment unread count for all other participants
                let participantIds = conversationDoc.data()?["participantIds"] as? [String] ?? []
                for participantId in participantIds {
                    if participantId != currentUserId {
                        let currentCount = updatedUnreadCounts[participantId] ?? 0
                        updatedUnreadCounts[participantId] = currentCount + 1
                    }
                }

                // Wrap conversation update with network simulation
                if let simulator = self?.networkSimulator {
                    try await simulator.execute {
                        try await conversationRef.setData([
                            "lastMessage": trimmed,
                            "lastMessageTimestamp": Timestamp(date: timestamp),
                            "lastSenderId": currentUserId,
                            "lastInteractionByUser": firestoreInteractionMap,
                            "unreadCount": updatedUnreadCounts,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], merge: true)
                    }
                } else {
                    try await conversationRef.setData([
                        "lastMessage": trimmed,
                        "lastMessageTimestamp": Timestamp(date: timestamp),
                        "lastSenderId": currentUserId,
                        "lastInteractionByUser": firestoreInteractionMap,
                        "unreadCount": updatedUnreadCounts,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)
                }

                // Update local conversation's lastInteractionByUser for sender
                await self?.updateLocalSenderInteraction(
                    conversationId: conversationId,
                    userId: currentUserId,
                    timestamp: timestamp,
                    lastMessage: trimmed
                )

                #if DEBUG
                print("[MessageSendingService] Message write completed successfully")
                #endif
            } catch {
                #if DEBUG
                print("[MessageSendingService] Message write failed: \(error.localizedDescription)")
                #endif
                await self?.markMessageAsFailed(messageId: messageId)
            }
        }

        pendingMessageTasks[messageId] = task
    }

    /// Retry sending a failed message
    /// - Parameter messageId: The message ID to retry
    /// - Throws: MessagingError or SwiftData errors
    func retryFailedMessage(messageId: String) async throws {
        guard let modelContext = modelContext, let currentUserId = currentUserId else {
            throw MessagingError.dataUnavailable
        }

        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == messageId
            }
        )
        descriptor.fetchLimit = 1

        guard let message = try modelContext.fetch(descriptor).first,
              message.deliveryState == .failed else {
            return
        }

        // Mark as pending again
        message.deliveryState = .pending
        message.updatedAt = Date()
        try modelContext.save()

        let conversationRef = db.collection("conversations").document(message.conversationId)
        let messageRef = conversationRef.collection("messages").document(messageId)

        // Include deliveryState as pending for retry
        let payload: [String: Any] = [
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "text": message.text,
            "timestamp": Timestamp(date: message.timestamp),
            "deliveryState": MessageDeliveryState.pending.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let task = Task { [weak self] in
            do {
                try await messageRef.setData(payload)

                #if DEBUG
                print("[MessageSendingService] Retry write queued successfully for \(messageId)")
                #endif

                // FirestoreSyncService will handle state transitions
            } catch {
                #if DEBUG
                print("[MessageSendingService] Retry failed for \(messageId): \(error.localizedDescription)")
                #endif
                await self?.markMessageAsFailed(messageId: messageId)
            }
        }

        pendingMessageTasks[messageId] = task
    }

    // MARK: - Private Helpers

    /// Mark message as failed using DeliveryStateTracker
    private func markMessageAsFailed(messageId: String) async {
        await deliveryStateTracker?.markAsFailed(messageId: messageId)
        pendingMessageTasks.removeValue(forKey: messageId)

        #if DEBUG
        print("[MessageSendingService] Message failed: \(messageId)")
        #endif
    }

    /// Update local conversation with sender's last interaction
    private func updateLocalSenderInteraction(
        conversationId: String,
        userId: String,
        timestamp: Date,
        lastMessage: String
    ) async {
        guard let modelContext = modelContext else { return }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )
        descriptor.fetchLimit = 1

        if let conversation = try? modelContext.fetch(descriptor).first {
            var interactions = conversation.lastInteractionByUser
            interactions[userId] = timestamp
            conversation.lastInteractionByUser = interactions
            conversation.lastSenderId = userId
            conversation.lastMessage = lastMessage
            conversation.lastMessageTimestamp = timestamp
            conversation.updatedAt = Date()
            try? modelContext.save()
        }
    }

    /// Parse timestamp dictionary from Firestore data
    private static func parseTimestampDictionary(_ value: Any?) -> [String: Date] {
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
