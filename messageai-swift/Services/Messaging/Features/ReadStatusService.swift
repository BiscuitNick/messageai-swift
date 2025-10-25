//
//  ReadStatusService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for managing read status and receipts
@MainActor
final class ReadStatusService {

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

    /// Mark a conversation as read by the current user
    /// Updates local unread count and lastInteractionByUser
    /// - Parameter conversationId: The conversation ID to mark as read
    func markConversationAsRead(_ conversationId: String) async {
        guard let modelContext = modelContext, let currentUserId = currentUserId else {
            return
        }

        let now = Date()

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )
        descriptor.fetchLimit = 1

        if let conversation = try? modelContext.fetch(descriptor).first {
            // Only update if there are new messages to mark as read
            let lastMessageTime = conversation.lastMessageTimestamp ?? .distantPast
            let currentInteractionTime = conversation.lastInteractionByUser[currentUserId] ?? .distantPast

            if lastMessageTime > currentInteractionTime {
                var unread = conversation.unreadCount
                unread[currentUserId] = 0
                conversation.unreadCount = unread

                var lastInteraction = conversation.lastInteractionByUser
                lastInteraction[currentUserId] = now
                conversation.lastInteractionByUser = lastInteraction

                conversation.updatedAt = now
                try? modelContext.save()

                // Get the full map to update in Firestore
                var firestoreInteractionMap: [String: Any] = [:]
                for (userId, date) in lastInteraction {
                    firestoreInteractionMap[userId] = Timestamp(date: date)
                }

                do {
                    try await db.collection("conversations").document(conversationId).setData([
                        "unreadCount.\(currentUserId)": 0,
                        "lastInteractionByUser": firestoreInteractionMap,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)

                    #if DEBUG
                    print("[ReadStatusService] Marked conversation as read: \(conversationId)")
                    #endif
                } catch {
                    debugLog("Failed to update unread state: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Mark all unread messages in a conversation as read by the current user
    /// Adds read receipts to all messages sent by other users
    /// - Parameter conversationId: The conversation ID
    /// - Throws: Firestore errors
    func markConversationMessagesAsRead(conversationId: String) async throws {
        guard let currentUserId = currentUserId else {
            throw MessagingError.dataUnavailable
        }

        let messagesRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")

        // Get all messages where current user hasn't read yet
        let snapshot = try await messagesRef.getDocuments()

        let batch = db.batch()
        var updateCount = 0
        let maxBatchSize = 500 // Firestore batch limit

        for document in snapshot.documents {
            let data = document.data()
            let senderId = data["senderId"] as? String ?? ""

            // Don't mark own messages as read
            if senderId == currentUserId {
                continue
            }

            // Check if current user already read this message
            let readReceipts = Self.parseReadReceipts(
                from: data,
                fallbackTimestamp: Date(),
                defaultReader: senderId
            )

            if !readReceipts.keys.contains(currentUserId) {
                // Mark as read
                let messageRef = messagesRef.document(document.documentID)
                batch.updateData([
                    "readReceipts.\(currentUserId)": FieldValue.serverTimestamp(),
                    "deliveryState": MessageDeliveryState.read.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: messageRef)

                updateCount += 1

                // Firestore has a 500 operation limit per batch
                if updateCount >= maxBatchSize {
                    break
                }
            }
        }

        if updateCount > 0 {
            try await batch.commit()

            #if DEBUG
            print("[ReadStatusService] Marked \(updateCount) messages as read in conversation: \(conversationId)")
            #endif
        }
    }

    // MARK: - Private Helpers

    /// Parse read receipts from Firestore data
    private static func parseReadReceipts(
        from data: [String: Any],
        fallbackTimestamp: Date,
        defaultReader: String? = nil
    ) -> [String: Date] {
        var receipts: [String: Date] = [:]

        if let map = data["readReceipts"] as? [String: Any] {
            for (userId, value) in map {
                if let timestamp = value as? Timestamp {
                    receipts[userId] = timestamp.dateValue()
                } else if let date = value as? Date {
                    receipts[userId] = date
                }
            }
        }

        if receipts.isEmpty, let readBy = data["readBy"] as? [String] {
            for userId in readBy {
                receipts[userId] = fallbackTimestamp
            }
        }

        if receipts.isEmpty, let defaultReader {
            receipts[defaultReader] = fallbackTimestamp
        }

        return receipts
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ReadStatusService]", message)
        #endif
    }
}
