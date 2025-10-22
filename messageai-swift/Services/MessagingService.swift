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
    struct DebugSnapshot {
        let isConfigured: Bool
        let currentUserId: String?
        let conversationListenerActive: Bool
        let activeMessageListeners: Int
        let pendingMessageTasks: Int
    }

    private let db: Firestore
    private var conversationListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var pendingMessageTasks: [String: Task<Void, Never>] = [:]

    private var modelContext: ModelContext?
    private var currentUserId: String?
    private let botUserId = "messageai-bot"

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
        guard let modelContext else { throw MessagingError.dataUnavailable }

        let filteredParticipants = participants.filter { $0 != currentUserId }
        guard !filteredParticipants.isEmpty else { throw MessagingError.invalidParticipants }

        let participantSet = Set(filteredParticipants + [currentUserId])

        if !isGroup {
            if let existingId = try findExistingLocalConversation(matching: participantSet, isGroup: false) {
                observeMessages(for: existingId)
                return existingId
            }

            if let (existingId, existingData) = try await findExistingRemoteConversation(
                matching: participantSet,
                currentUserId: currentUserId,
                isGroup: false
            ) {
                try cacheConversation(
                    id: existingId,
                    data: existingData,
                    participantSet: participantSet,
                    isGroup: false,
                    currentUserId: currentUserId
                )
                observeMessages(for: existingId)
                return existingId
            }
        }

        let conversationRef = db.collection("conversations").document()
        let now = Date()

        var data: [String: Any] = [
            "participantIds": Array(participantSet),
            "isGroup": isGroup,
            "adminIds": [currentUserId],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "unreadCount": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) })
        ]

        let trimmedGroupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedGroupName, !trimmedGroupName.isEmpty {
            data["groupName"] = trimmedGroupName
        }

        try await conversationRef.setData(data)

        let conversationId = conversationRef.documentID

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )
        descriptor.fetchLimit = 1

        if try modelContext.fetch(descriptor).first == nil {
            let conversationEntity = ConversationEntity(
                id: conversationId,
                participantIds: Array(participantSet),
                isGroup: isGroup,
                groupName: trimmedGroupName,
                groupPictureURL: nil,
                adminIds: [currentUserId],
                lastMessage: nil,
                lastMessageTimestamp: nil,
                unreadCount: Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) }),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(conversationEntity)
            try modelContext.save()
        }

        observeMessages(for: conversationId)

        return conversationId
    }

    var debugSnapshot: DebugSnapshot {
        DebugSnapshot(
            isConfigured: modelContext != nil && currentUserId != nil,
            currentUserId: currentUserId,
            conversationListenerActive: conversationListener != nil,
            activeMessageListeners: messageListeners.count,
            pendingMessageTasks: pendingMessageTasks.count
        )
    }

    private func findExistingLocalConversation(matching participantSet: Set<String>, isGroup: Bool) throws -> String? {
        guard let modelContext else { return nil }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.isGroup == isGroup
            }
        )

        let candidates = try modelContext.fetch(descriptor)
        return candidates.first { Set($0.participantIds) == participantSet }?.id
    }

    private func findExistingRemoteConversation(
        matching participantSet: Set<String>,
        currentUserId: String,
        isGroup: Bool
    ) async throws -> (String, [String: Any])? {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()

        for document in snapshot.documents {
            let data = document.data()
            let participants = stringArray(from: data["participantIds"])
            let participantComparisonSet = Set(participants)
            let documentIsGroup = data["isGroup"] as? Bool ?? false

            if participantComparisonSet == participantSet && documentIsGroup == isGroup {
                return (document.documentID, data)
            }
        }

        return nil
    }

    private func cacheConversation(
        id: String,
        data: [String: Any],
        participantSet: Set<String>,
        isGroup: Bool,
        currentUserId: String
    ) throws {
        let participants = stringArray(from: data["participantIds"])
        let adminIds = stringArray(from: data["adminIds"])
        let resolvedParticipants = participants.isEmpty ? Array(participantSet) : participants
        let resolvedAdminIds = adminIds.isEmpty ? [currentUserId] : adminIds
        let groupName = data["groupName"] as? String
        let groupPictureURL = data["groupPictureURL"] as? String
        let lastMessage = data["lastMessage"] as? String
        let lastTimestamp = (data["lastMessageTimestamp"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let unreadCount = parseUnreadCount(data["unreadCount"], participants: resolvedParticipants)

        try upsertLocalConversation(
            id: id,
            participantIds: resolvedParticipants,
            isGroup: isGroup,
            groupName: groupName,
            groupPictureURL: groupPictureURL,
            adminIds: resolvedAdminIds,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastTimestamp,
            unreadCount: unreadCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func parseUnreadCount(_ value: Any?, participants: [String]) -> [String: Int] {
        guard let raw = value as? [String: Any] else {
            return Dictionary(uniqueKeysWithValues: participants.map { ($0, 0) })
        }

        var result: [String: Int] = [:]
        for (key, entry) in raw {
            if let intValue = entry as? Int {
                result[key] = intValue
            } else if let numberValue = entry as? NSNumber {
                result[key] = numberValue.intValue
            }
        }

        if result.isEmpty {
            participants.forEach { result[$0] = 0 }
        }

        return result
    }

    private func stringArray(from value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }
        return []
    }

    func ensureBotConversation() async throws -> String {
        guard let currentUserId else { throw MessagingError.notAuthenticated }
        guard let modelContext else { throw MessagingError.dataUnavailable }

        let now = Date()
        let botRef = db.collection("users").document(botUserId)
        try await botRef.setData([
            "email": "bot@messageai.app",
            "displayName": "MessageAI Bot",
            "isOnline": true,
            "lastSeen": Timestamp(date: now),
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)

        let conversationId = "bot-\(currentUserId)"
        let conversationRef = db.collection("conversations").document(conversationId)
        var conversationDoc = try await conversationRef.getDocument()

        let welcomeText = "Hi! I'm your MessageAI bot. Ask me anything to get started."
        let participantIds = [currentUserId, botUserId]
        let unreadCount = [currentUserId: 1, botUserId: 0]

        if !conversationDoc.exists {
            try await conversationRef.setData([
                "participantIds": participantIds,
                "isGroup": false,
                "adminIds": [currentUserId],
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "lastMessage": welcomeText,
                "lastMessageTimestamp": Timestamp(date: now),
                "unreadCount": unreadCount
            ])

            let messageRef = conversationRef.collection("messages").document("bot-intro")
            try await messageRef.setData([
                "conversationId": conversationId,
                "senderId": botUserId,
                "text": welcomeText,
                "timestamp": Timestamp(date: now),
                "deliveryStatus": DeliveryStatus.delivered.rawValue,
                "readBy": [botUserId],
                "updatedAt": FieldValue.serverTimestamp()
            ])

            conversationDoc = try await conversationRef.getDocument()
        }

        let conversationData = conversationDoc.data() ?? [:]
        let lastMessage = conversationData["lastMessage"] as? String ?? welcomeText
        let lastMessageTimestamp = (conversationData["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? now
        let unread = conversationData["unreadCount"] as? [String: Int] ?? unreadCount
        let createdAt = (conversationData["createdAt"] as? Timestamp)?.dateValue() ?? now
        let updatedAt = (conversationData["updatedAt"] as? Timestamp)?.dateValue() ?? now

        try upsertLocalUser(
            id: botUserId,
            email: "bot@messageai.app",
            displayName: "MessageAI Bot",
            profilePictureURL: nil,
            isOnline: true,
            lastSeen: now,
            createdAt: createdAt
        )

        try upsertLocalConversation(
            id: conversationId,
            participantIds: participantIds,
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [currentUserId],
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            unreadCount: unread,
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
                "deliveryStatus": DeliveryStatus.delivered.rawValue,
                "readBy": [botUserId],
                "updatedAt": FieldValue.serverTimestamp()
            ])
            messageDoc = try await messageRef.getDocument()
        }

        let messageData = messageDoc.data() ?? [:]
        let messageTimestamp = (messageData["timestamp"] as? Timestamp)?.dateValue() ?? now
        let messageText = messageData["text"] as? String ?? welcomeText
        let messageSenderId = messageData["senderId"] as? String ?? botUserId
        let messageStatusRaw = messageData["deliveryStatus"] as? String ?? DeliveryStatus.delivered.rawValue
        let messageStatus = DeliveryStatus(rawValue: messageStatusRaw) ?? .delivered
        let messageReadBy = messageData["readBy"] as? [String] ?? [botUserId]

        try upsertLocalMessage(
            id: "bot-intro",
            conversationId: conversationId,
            senderId: messageSenderId,
            text: messageText,
            timestamp: messageTimestamp,
            deliveryStatus: messageStatus,
            readBy: messageReadBy
        )

        observeMessages(for: conversationId)
        return conversationId
    }

    func seedMockData() async throws {
        guard let currentUserId else { throw MessagingError.notAuthenticated }
        guard let modelContext else { throw MessagingError.dataUnavailable }

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

            try upsertLocalUser(
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
                "unreadCount": demoUnread
            ])

            let messageRef = demoConversationRef.collection("messages").document("demo-intro")
            try await messageRef.setData([
                "conversationId": demoConversationId,
                "senderId": primarySample.id,
                "text": demoMessageText,
                "timestamp": Timestamp(date: now),
                "deliveryStatus": DeliveryStatus.delivered.rawValue,
                "readBy": [primarySample.id],
                "updatedAt": FieldValue.serverTimestamp()
            ])

            demoConversationDoc = try await demoConversationRef.getDocument()
        }

        let demoData = demoConversationDoc.data() ?? [:]
        let demoLastMessage = demoData["lastMessage"] as? String ?? demoMessageText
        let demoLastTimestamp = (demoData["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? now
        let demoUnreadCount = demoData["unreadCount"] as? [String: Int] ?? demoUnread
        let demoCreatedAt = (demoData["createdAt"] as? Timestamp)?.dateValue() ?? now
        let demoUpdatedAt = (demoData["updatedAt"] as? Timestamp)?.dateValue() ?? now

        try upsertLocalConversation(
            id: demoConversationId,
            participantIds: demoParticipantIds,
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [currentUserId],
            lastMessage: demoLastMessage,
            lastMessageTimestamp: demoLastTimestamp,
            unreadCount: demoUnreadCount,
            createdAt: demoCreatedAt,
            updatedAt: demoUpdatedAt
        )

        let demoMessageRef = demoConversationRef.collection("messages").document("demo-intro")
        var demoMessageDoc = try await demoMessageRef.getDocument()
        if !demoMessageDoc.exists {
            try await demoMessageRef.setData([
                "conversationId": demoConversationId,
                "senderId": primarySample.id,
                "text": demoMessageText,
                "timestamp": Timestamp(date: now),
                "deliveryStatus": DeliveryStatus.delivered.rawValue,
                "readBy": [primarySample.id],
                "updatedAt": FieldValue.serverTimestamp()
            ])
            demoMessageDoc = try await demoMessageRef.getDocument()
        }

        let demoMessageData = demoMessageDoc.data() ?? [:]
        let demoMessageTimestamp = (demoMessageData["timestamp"] as? Timestamp)?.dateValue() ?? now
        let demoMessageSender = demoMessageData["senderId"] as? String ?? primarySample.id
        let demoMessageStatusRaw = demoMessageData["deliveryStatus"] as? String ?? DeliveryStatus.delivered.rawValue
        let demoMessageStatus = DeliveryStatus(rawValue: demoMessageStatusRaw) ?? .delivered
        let demoMessageReadBy = demoMessageData["readBy"] as? [String] ?? [primarySample.id]
        let demoMessageBody = demoMessageData["text"] as? String ?? demoMessageText

        try upsertLocalMessage(
            id: "demo-intro",
            conversationId: demoConversationId,
            senderId: demoMessageSender,
            text: demoMessageBody,
            timestamp: demoMessageTimestamp,
            deliveryStatus: demoMessageStatus,
            readBy: demoMessageReadBy
        )

        observeMessages(for: demoConversationId)
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

    func ensureMessageListener(for conversationId: String) {
        observeMessages(for: conversationId)
    }

    func markConversationAsRead(_ conversationId: String) async {
        guard let modelContext, let currentUserId else { return }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )
        descriptor.fetchLimit = 1

        if let conversation = try? modelContext.fetch(descriptor).first {
            var unread = conversation.unreadCount
            unread[currentUserId] = 0
            conversation.unreadCount = unread
            conversation.updatedAt = Date()
            try? modelContext.save()
        }

        do {
            try await db.collection("conversations").document(conversationId).setData([
                "unreadCount.\(currentUserId)": 0,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            debugLog("Failed to update unread state: \(error.localizedDescription)")
        }

        await markMessagesAsRead(for: conversationId, userId: currentUserId)
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
            let shouldMarkDelivered: Bool = {
                guard let currentUserId else { return false }
                return senderId != currentUserId && status == .sent
            }()
            let finalStatus: DeliveryStatus = shouldMarkDelivered ? .delivered : status

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
                    existing.deliveryStatus = finalStatus
                    existing.readBy = readBy
                    existing.updatedAt = updatedAt
                } else {
                    let message = MessageEntity(
                        id: messageId,
                        conversationId: conversationId,
                        senderId: senderId,
                        text: text,
                        timestamp: timestamp,
                        deliveryStatus: finalStatus,
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

        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let senderId = data["senderId"] as? String,
                let statusRaw = data["deliveryStatus"] as? String,
                let currentUserId
            else { continue }

            if senderId != currentUserId, statusRaw == DeliveryStatus.sent.rawValue {
                let messageId = change.document.documentID
                Task {
                    do {
                        let messageRef = db.collection("conversations")
                            .document(conversationId)
                            .collection("messages")
                            .document(messageId)
                        try await messageRef.setData([
                            "deliveryStatus": DeliveryStatus.delivered.rawValue,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], merge: true)
                    } catch {
                        debugLog("Failed to mark message delivered: \(error.localizedDescription)")
                    }
                }
            }
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

    private func markMessagesAsRead(for conversationId: String, userId: String) async {
        guard let modelContext else { return }

        let readStatus = DeliveryStatus.read.rawValue
        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.conversationId == conversationId &&
                message.senderId != userId &&
                message.deliveryStatusRawValue != readStatus
            }
        )

        let unreadMessages = (try? modelContext.fetch(descriptor)) ?? []

        guard !unreadMessages.isEmpty else { return }

        for message in unreadMessages {
            message.deliveryStatus = .read
            if !message.readBy.contains(userId) {
                var updatedReadBy = message.readBy
                updatedReadBy.append(userId)
                message.readBy = updatedReadBy
            }
            message.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to save read state locally: \(error.localizedDescription)")
        }

        for message in unreadMessages {
            let messageRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(message.id)

            do {
                try await messageRef.setData([
                    "deliveryStatus": DeliveryStatus.read.rawValue,
                    "readBy": FieldValue.arrayUnion([userId]),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                debugLog("Failed to sync read receipt: \(error.localizedDescription)")
            }
        }
    }

    private func upsertLocalUser(
        id: String,
        email: String,
        displayName: String,
        profilePictureURL: String?,
        isOnline: Bool,
        lastSeen: Date,
        createdAt: Date
    ) throws {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.email = email
            existing.displayName = displayName
            existing.profilePictureURL = profilePictureURL
            existing.isOnline = isOnline
            existing.lastSeen = lastSeen
        } else {
            let user = UserEntity(
                id: id,
                email: email,
                displayName: displayName,
                profilePictureURL: profilePictureURL,
                isOnline: isOnline,
                lastSeen: lastSeen,
                createdAt: createdAt
            )
            modelContext.insert(user)
        }

        try modelContext.save()
    }

    private func upsertLocalConversation(
        id: String,
        participantIds: [String],
        isGroup: Bool,
        groupName: String?,
        groupPictureURL: String?,
        adminIds: [String],
        lastMessage: String?,
        lastMessageTimestamp: Date?,
        unreadCount: [String: Int],
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.participantIds = participantIds
            existing.isGroup = isGroup
            existing.groupName = groupName
            existing.groupPictureURL = groupPictureURL
            existing.adminIds = adminIds
            existing.lastMessage = lastMessage
            existing.lastMessageTimestamp = lastMessageTimestamp
            existing.unreadCount = unreadCount
            existing.createdAt = createdAt
            existing.updatedAt = updatedAt
        } else {
            let conversation = ConversationEntity(
                id: id,
                participantIds: participantIds,
                isGroup: isGroup,
                groupName: groupName,
                groupPictureURL: groupPictureURL,
                adminIds: adminIds,
                lastMessage: lastMessage,
                lastMessageTimestamp: lastMessageTimestamp,
                unreadCount: unreadCount,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            modelContext.insert(conversation)
        }

        try modelContext.save()
    }

    private func upsertLocalMessage(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date,
        deliveryStatus: DeliveryStatus,
        readBy: [String]
    ) throws {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.conversationId = conversationId
            existing.senderId = senderId
            existing.text = text
            existing.timestamp = timestamp
            existing.deliveryStatus = deliveryStatus
            existing.readBy = readBy
            existing.updatedAt = timestamp
        } else {
            let message = MessageEntity(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                text: text,
                timestamp: timestamp,
                deliveryStatus: deliveryStatus,
                readBy: readBy,
                updatedAt: timestamp
            )
            modelContext.insert(message)
        }

        try modelContext.save()
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MessagingService]", message)
        #endif
    }
}

enum MessagingError: Error, LocalizedError {
    case notAuthenticated
    case invalidParticipants
    case dataUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to send messages."
        case .invalidParticipants:
            return "Select at least one other participant."
        case .dataUnavailable:
            return "Local data store not ready. Try again shortly."
        }
    }
}
