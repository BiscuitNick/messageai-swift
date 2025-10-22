//
//  MessagingService.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import Observation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class MessagingService {
    private let db: Firestore
    private var conversationListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var pendingMessageTasks: [String: Task<Void, Never>] = [:]

    private var modelContext: ModelContext?
    private var currentUserId: String?

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(modelContext: ModelContext, currentUserId: String) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
        observeConversations(for: currentUserId)
    }

    func reset() {
        conversationListener?.remove()
        conversationListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        pendingMessageTasks.values.forEach { $0.cancel() }
        pendingMessageTasks.removeAll()
        currentUserId = nil
    }

    func createConversation(with participants: [String], isGroup: Bool = false, groupName: String? = nil) async throws -> String {
        guard let currentUserId else { throw MessagingError.notAuthenticated }
        let participantSet = Set(participants + [currentUserId])
        let conversationRef = db.collection("conversations").document()

        var data: [String: Any] = [
            "participantIds": Array(participantSet),
            "isGroup": isGroup,
            "adminIds": [currentUserId],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "unreadCount": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) })
        ]

        data["groupName"] = groupName

        try await conversationRef.setData(data)
        return conversationRef.documentID
    }

    func sendMessage(conversationId: String, text: String) async throws {
        guard let currentUserId, let modelContext else {
            throw MessagingError.notAuthenticated
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = Date()
        let messageId = UUID().uuidString
        let optimisticMessage = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            text: trimmed,
            timestamp: timestamp,
            deliveryStatus: .sending,
            readBy: [currentUserId],
            updatedAt: timestamp
        )

        modelContext.insert(optimisticMessage)
        try? modelContext.save()

        let conversationRef = db.collection("conversations").document(conversationId)
        let messageRef = conversationRef.collection("messages").document(messageId)

        let payload: [String: Any] = [
            "conversationId": conversationId,
            "senderId": currentUserId,
            "text": trimmed,
            "timestamp": Timestamp(date: timestamp),
            "deliveryStatus": DeliveryStatus.sent.rawValue,
            "readBy": [currentUserId],
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let task = Task { [weak self] in
            do {
                try await messageRef.setData(payload)
                try await conversationRef.setData([
                    "lastMessage": trimmed,
                    "lastMessageTimestamp": Timestamp(date: timestamp),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)

                try await self?.markMessageAsSent(messageId: messageId)
            } catch {
                await self?.markMessageAsFailed(messageId: messageId)
            }
        }

        pendingMessageTasks[messageId] = task
    }

    private func observeConversations(for userId: String) {
        conversationListener?.remove()
        conversationListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Conversation listener error: \(error.localizedDescription)")
                    return
                }

                Task { @MainActor in
                    await self.handleConversationSnapshot(snapshot)
                }
            }
    }

    private func observeMessages(for conversationId: String) {
        if let existing = messageListeners[conversationId] {
            existing.remove()
        }

        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Message listener error: \(error.localizedDescription)")
                    return
                }

                Task { @MainActor in
                    await self.handleMessageSnapshot(conversationId: conversationId, snapshot: snapshot)
                }
            }

        messageListeners[conversationId] = listener
    }

    private func handleConversationSnapshot(_ snapshot: QuerySnapshot?) async {
        guard let snapshot, let modelContext, let currentUserId else { return }

        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let participantIds = data["participantIds"] as? [String],
                let isGroup = data["isGroup"] as? Bool,
                let adminIds = data["adminIds"] as? [String]
            else {
                continue
            }

            let conversationId = change.document.documentID
            let lastMessage = data["lastMessage"] as? String
            let lastTimestamp = (data["lastMessageTimestamp"] as? Timestamp)?.dateValue()
            let unreadCount = data["unreadCount"] as? [String: Int] ?? [:]
            let groupName = data["groupName"] as? String
            let groupPictureURL = data["groupPictureURL"] as? String
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            var descriptor = FetchDescriptor<ConversationEntity>(
                predicate: #Predicate<ConversationEntity> { conversation in
                    conversation.id == conversationId
                }
            )
            descriptor.fetchLimit = 1

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.participantIds = participantIds
                    existing.isGroup = isGroup
                    existing.adminIds = adminIds
                    existing.lastMessage = lastMessage
                    existing.lastMessageTimestamp = lastTimestamp
                    existing.unreadCount = unreadCount
                    existing.groupName = groupName
                    existing.groupPictureURL = groupPictureURL
                    existing.updatedAt = updatedAt
                } else {
                    let conversation = ConversationEntity(
                        id: conversationId,
                        participantIds: participantIds,
                        isGroup: isGroup,
                        groupName: groupName,
                        groupPictureURL: groupPictureURL,
                        adminIds: adminIds,
                        lastMessage: lastMessage,
                        lastMessageTimestamp: lastTimestamp,
                        unreadCount: unreadCount,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )

                    modelContext.insert(conversation)
                }

                observeMessages(for: conversationId)
            case .removed:
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
                if let listener = messageListeners[conversationId] {
                    listener.remove()
                    messageListeners.removeValue(forKey: conversationId)
                }
            }
        }

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to save conversations: \(error.localizedDescription)")
        }
    }

    private func handleMessageSnapshot(conversationId: String, snapshot: QuerySnapshot?) async {
        guard let snapshot, let modelContext else { return }

        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let senderId = data["senderId"] as? String,
                let text = data["text"] as? String,
                let statusRaw = data["deliveryStatus"] as? String
            else {
                continue
            }

            let messageId = change.document.documentID
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            let readBy = data["readBy"] as? [String] ?? []
            let status = DeliveryStatus(rawValue: statusRaw) ?? .sent

            var descriptor = FetchDescriptor<MessageEntity>(
                predicate: #Predicate<MessageEntity> { message in
                    message.id == messageId
                }
            )
            descriptor.fetchLimit = 1

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.text = text
                    existing.timestamp = timestamp
                    existing.deliveryStatus = status
                    existing.readBy = readBy
                    existing.updatedAt = updatedAt
                } else {
                    let message = MessageEntity(
                        id: messageId,
                        conversationId: conversationId,
                        senderId: senderId,
                        text: text,
                        timestamp: timestamp,
                        deliveryStatus: status,
                        readBy: readBy,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(message)
                }
            case .removed:
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        }

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to save messages: \(error.localizedDescription)")
        }
    }

    private func markMessageAsSent(messageId: String) async throws {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == messageId
            }
        )
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.deliveryStatus = .sent
            message.updatedAt = Date()
            try modelContext.save()
        }

        pendingMessageTasks.removeValue(forKey: messageId)
    }

    private func markMessageAsFailed(messageId: String) async {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == messageId
            }
        )
        descriptor.fetchLimit = 1

        if let message = try? modelContext.fetch(descriptor).first {
            message.deliveryStatus = .sending
            message.updatedAt = Date()
            try? modelContext.save()
        }

        pendingMessageTasks.removeValue(forKey: messageId)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MessagingService]", message)
        #endif
    }
}

enum MessagingError: Error, LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to send messages."
        }
    }
}
