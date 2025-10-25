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
    private var messageListenerStartTimes: [String: Date] = [:]

    private var modelContext: ModelContext?
    private var currentUserId: String?
    private let botUserId = "dash-bot"  // Legacy bot user ID
    private var notificationService: NotificationService?
    private var networkSimulator: NetworkSimulator?
    private var isAppInForeground: Bool = true

    // AI Features Callback
    var onMessageMutation: ((String, String) -> Void)?  // (conversationId, messageId)

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(modelContext: ModelContext, currentUserId: String, notificationService: NotificationService? = nil, networkSimulator: NetworkSimulator? = nil) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
        self.notificationService = notificationService
        self.networkSimulator = networkSimulator
        observeConversations(for: currentUserId)
    }

    /// Parse delivery state from Firestore data with backward compatibility
    private static func parseDeliveryState(from data: [String: Any], fallback: MessageDeliveryState = .sent) -> MessageDeliveryState {
        // Try new field first
        if let stateRaw = data["deliveryState"] as? String {
            return MessageDeliveryState(fromLegacy: stateRaw)
        }
        // Fall back to legacy field
        if let statusRaw = data["deliveryState"] as? String {
            return MessageDeliveryState(fromLegacy: statusRaw)
        }
        return fallback
    }

    func setAppInForeground(_ isInForeground: Bool) {
        self.isAppInForeground = isInForeground
    }

    func reset() {
        conversationListener?.remove()
        conversationListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        messageListenerStartTimes.removeAll()
        pendingMessageTasks.values.forEach { $0.cancel() }
        pendingMessageTasks.removeAll()
        currentUserId = nil
        onMessageMutation = nil
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
            "unreadCount": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) }),
            "lastInteractionByUser": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, Timestamp(date: now)) })
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
                lastSenderId: nil,
                unreadCount: Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) }),
                lastInteractionByUser: Dictionary(uniqueKeysWithValues: participantSet.map { ($0, now) }),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(conversationEntity)
            try modelContext.save()
        }

        observeMessages(for: conversationId)

        return conversationId
    }

    func createConversationWithBot(botId: String) async throws -> String {
        guard let currentUserId else { throw MessagingError.notAuthenticated }
        guard let modelContext else { throw MessagingError.dataUnavailable }

        // ALWAYS create a new conversation with bots, never resume existing
        // Use bot: prefix for bot participant IDs
        let prefixedBotId = "bot:\(botId)"
        let conversationRef = db.collection("conversations").document()
        let conversationId = conversationRef.documentID
        let now = Date()
        let participantIds = [currentUserId, prefixedBotId]

        let welcomeText = welcomeMessage(for: botId)

        var data: [String: Any] = [
            "participantIds": participantIds,
            "isGroup": false,
            "adminIds": [currentUserId],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "lastMessage": welcomeText,
            "lastMessageTimestamp": Timestamp(date: now),
            "lastSenderId": prefixedBotId,
            "unreadCount": [currentUserId: 0, prefixedBotId: 0],
            "lastInteractionByUser": [
                currentUserId: Timestamp(date: now),
                prefixedBotId: Timestamp(date: now)
            ]
        ]

        try await conversationRef.setData(data)

        // Create local conversation
        let conversationEntity = ConversationEntity(
            id: conversationId,
            participantIds: participantIds,
            isGroup: false,
            groupName: nil,
            groupPictureURL: nil,
            adminIds: [currentUserId],
            lastMessage: welcomeText,
            lastMessageTimestamp: now,
            lastSenderId: prefixedBotId,
            unreadCount: [currentUserId: 0, prefixedBotId: 0],
            lastInteractionByUser: [currentUserId: now, prefixedBotId: now],
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(conversationEntity)
        try modelContext.save()

        // Create welcome message
        let welcomeMessageId = "welcome-\(conversationId)"
        let messageRef = conversationRef.collection("messages").document(welcomeMessageId)
        try await messageRef.setData([
            "conversationId": conversationId,
            "senderId": prefixedBotId,
            "text": welcomeText,
            "timestamp": Timestamp(date: now),
            "deliveryState": MessageDeliveryState.delivered.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])

        // Create local welcome message
        let welcomeMessage = MessageEntity(
            id: welcomeMessageId,
            conversationId: conversationId,
            senderId: prefixedBotId,
            text: welcomeText,
            timestamp: now,
            deliveryState: .delivered,
            readReceipts: [prefixedBotId: now],
            updatedAt: now
        )
        modelContext.insert(welcomeMessage)
        try modelContext.save()

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
        let lastSenderId = data["lastSenderId"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let unreadCount = parseUnreadCount(data["unreadCount"], participants: resolvedParticipants)
        let lastInteractionByUser = Self.parseTimestampDictionary(data["lastInteractionByUser"])

        try upsertLocalConversation(
            id: id,
            participantIds: resolvedParticipants,
            isGroup: isGroup,
            groupName: groupName,
            groupPictureURL: groupPictureURL,
            adminIds: resolvedAdminIds,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastTimestamp,
            lastSenderId: lastSenderId,
            unreadCount: unreadCount,
            lastInteractionByUser: lastInteractionByUser,
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

        let welcomeText = welcomeMessage(for: botUserId)
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
        var lastInteractionByUser = Self.parseTimestampDictionary(conversationData["lastInteractionByUser"])
        if lastInteractionByUser[currentUserId] == nil {
            lastInteractionByUser[currentUserId] = now
        }
        if lastInteractionByUser[botUserId] == nil {
            lastInteractionByUser[botUserId] = now
        }

        try upsertLocalUser(
            id: botUserId,
            email: "bot@messageai.app",
            displayName: "Dash Bot",
            profilePictureURL: "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
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

        let messageData = messageDoc.data() ?? [:]
        let messageTimestamp = (messageData["timestamp"] as? Timestamp)?.dateValue() ?? now
        let messageText = messageData["text"] as? String ?? welcomeText
        let messageSenderId = messageData["senderId"] as? String ?? botUserId
        let messageStatusRaw = messageData["deliveryState"] as? String ?? MessageDeliveryState.delivered.rawValue
        let messageStatus = DeliveryStatus(rawValue: messageStatusRaw) ?? .delivered
        let messageReadReceipts = Self.parseReadReceipts(
            from: messageData,
            fallbackTimestamp: messageTimestamp,
            defaultReader: botUserId
        )

        try upsertLocalMessage(
            id: "bot-intro",
            conversationId: conversationId,
            senderId: messageSenderId,
            text: messageText,
            timestamp: messageTimestamp,
            deliveryState: messageStatus.toDeliveryState,
            readReceipts: messageReadReceipts
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

        let demoData = demoConversationDoc.data() ?? [:]
        let demoLastMessage = demoData["lastMessage"] as? String ?? demoMessageText
        let demoLastTimestamp = (demoData["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? now
        let demoLastSenderId = demoData["lastSenderId"] as? String
        let demoUnreadCount = demoData["unreadCount"] as? [String: Int] ?? demoUnread
        let demoCreatedAt = (demoData["createdAt"] as? Timestamp)?.dateValue() ?? now
        let demoUpdatedAt = (demoData["updatedAt"] as? Timestamp)?.dateValue() ?? now
        var demoLastInteractionByUser = Self.parseTimestampDictionary(demoData["lastInteractionByUser"])
        if demoLastInteractionByUser[currentUserId] == nil {
            demoLastInteractionByUser[currentUserId] = now
        }
        if demoLastInteractionByUser[primarySample.id] == nil {
            demoLastInteractionByUser[primarySample.id] = now
        }

        try upsertLocalConversation(
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

        let demoMessageRef = demoConversationRef.collection("messages").document("demo-intro")
        var demoMessageDoc = try await demoMessageRef.getDocument()
        if !demoMessageDoc.exists {
            try await demoMessageRef.setData([
                "conversationId": demoConversationId,
                "senderId": primarySample.id,
                "text": demoMessageText,
                "timestamp": Timestamp(date: now),
                "deliveryState": MessageDeliveryState.delivered.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            demoMessageDoc = try await demoMessageRef.getDocument()
        }

        let demoMessageData = demoMessageDoc.data() ?? [:]
        let demoMessageTimestamp = (demoMessageData["timestamp"] as? Timestamp)?.dateValue() ?? now
        let demoMessageSender = demoMessageData["senderId"] as? String ?? primarySample.id
        let demoMessageStatusRaw = demoMessageData["deliveryState"] as? String ?? MessageDeliveryState.delivered.rawValue
        let demoMessageStatus = DeliveryStatus(rawValue: demoMessageStatusRaw) ?? .delivered
        let demoMessageReadReceipts = Self.parseReadReceipts(
            from: demoMessageData,
            fallbackTimestamp: demoMessageTimestamp,
            defaultReader: primarySample.id
        )
        let demoMessageBody = demoMessageData["text"] as? String ?? demoMessageText

        try upsertLocalMessage(
            id: "demo-intro",
            conversationId: demoConversationId,
            senderId: demoMessageSender,
            text: demoMessageBody,
            timestamp: demoMessageTimestamp,
            deliveryState: demoMessageStatus.toDeliveryState,
            readReceipts: demoMessageReadReceipts
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
            deliveryState: .pending,
            readReceipts: [:],
            updatedAt: timestamp
        )

        modelContext.insert(optimisticMessage)
        try? modelContext.save()

        // Notify AI Features of new message
        onMessageMutation?(conversationId, messageId)

        let conversationRef = db.collection("conversations").document(conversationId)
        let messageRef = conversationRef.collection("messages").document(messageId)

        let payload: [String: Any] = [
            "conversationId": conversationId,
            "senderId": currentUserId,
            "text": trimmed,
            "timestamp": Timestamp(date: timestamp),
            "deliveryState": MessageDeliveryState.sent.rawValue,
            // Legacy field for backward compatibility
            "deliveryStatus": "sent",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let task = Task { [weak self] in
            do {
                // Wrap Firestore setData with network simulation
                if let simulator = self?.networkSimulator {
                    try await simulator.execute {
                        try await messageRef.setData(payload)
                    }
                } else {
                    try await messageRef.setData(payload)
                }

                // Get current conversation to update lastInteractionByUser
                let conversationDoc: DocumentSnapshot
                if let simulator = self?.networkSimulator {
                    conversationDoc = try await simulator.execute {
                        try await conversationRef.getDocument()
                    }
                } else {
                    conversationDoc = try await conversationRef.getDocument()
                }

                var lastInteractionByUser = Self.parseTimestampDictionary(conversationDoc.data()?["lastInteractionByUser"])
                lastInteractionByUser[currentUserId] = timestamp

                // Convert to Firestore format
                var firestoreInteractionMap: [String: Any] = [:]
                for (userId, date) in lastInteractionByUser {
                    firestoreInteractionMap[userId] = Timestamp(date: date)
                }

                // Wrap conversation update with network simulation
                if let simulator = self?.networkSimulator {
                    try await simulator.execute {
                        try await conversationRef.setData([
                            "lastMessage": trimmed,
                            "lastMessageTimestamp": Timestamp(date: timestamp),
                            "lastSenderId": currentUserId,
                            "lastInteractionByUser": firestoreInteractionMap,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], merge: true)
                    }
                } else {
                    try await conversationRef.setData([
                        "lastMessage": trimmed,
                        "lastMessageTimestamp": Timestamp(date: timestamp),
                        "lastSenderId": currentUserId,
                        "lastInteractionByUser": firestoreInteractionMap,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)
                }

                // Update local conversation's lastInteractionByUser for sender
                await self?.updateLocalSenderInteraction(conversationId: conversationId, userId: currentUserId, timestamp: timestamp, lastMessage: trimmed)

                try await self?.markMessageAsSent(messageId: messageId)
            } catch {
                await self?.markMessageAsFailed(messageId: messageId)
            }
        }

        pendingMessageTasks[messageId] = task
    }

    func sendMessageAsBot(conversationId: String, text: String, botUserId: String) async throws {
        guard let modelContext else {
            throw MessagingError.dataUnavailable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = Date()
        let messageId = UUID().uuidString

        // Notify AI Features of new bot message
        onMessageMutation?(conversationId, messageId)

        // Create optimistic local message for immediate UI update
        let optimisticMessage = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            senderId: botUserId,
            text: trimmed,
            timestamp: timestamp,
            deliveryState: .sent,
            readReceipts: [botUserId: timestamp],
            updatedAt: timestamp
        )

        modelContext.insert(optimisticMessage)
        try? modelContext.save()

        let conversationRef = db.collection("conversations").document(conversationId)
        let messageRef = conversationRef.collection("messages").document(messageId)

        let payload: [String: Any] = [
            "conversationId": conversationId,
            "senderId": botUserId,
            "text": trimmed,
            "timestamp": Timestamp(date: timestamp),
            "deliveryState": MessageDeliveryState.sent.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await messageRef.setData(payload)

            // Update conversation metadata
            let conversationDoc = try await conversationRef.getDocument()
            var lastInteractionByUser = Self.parseTimestampDictionary(conversationDoc.data()?["lastInteractionByUser"])
            lastInteractionByUser[botUserId] = timestamp

            var firestoreInteractionMap: [String: Any] = [:]
            for (userId, date) in lastInteractionByUser {
                firestoreInteractionMap[userId] = Timestamp(date: date)
            }

            try await conversationRef.setData([
                "lastMessage": trimmed,
                "lastMessageTimestamp": Timestamp(date: timestamp),
                "lastSenderId": botUserId,
                "lastInteractionByUser": firestoreInteractionMap,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            // Update local conversation
            await updateLocalSenderInteraction(conversationId: conversationId, userId: botUserId, timestamp: timestamp, lastMessage: trimmed)
        } catch {
            debugLog("Failed to send bot message: \(error.localizedDescription)")
            throw error
        }
    }

    func ensureMessageListener(for conversationId: String) {
        observeMessages(for: conversationId)
    }

    func markConversationAsRead(_ conversationId: String) async {
        guard let modelContext, let currentUserId else { return }

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
                } catch {
                    debugLog("Failed to update unread state: \(error.localizedDescription)")
                }
            }
        }
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

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleConversationSnapshot(snapshot)
                }
            }
    }

    private func observeMessages(for conversationId: String) {
        if let existing = messageListeners[conversationId] {
            existing.remove()
        }

        // Record when this listener starts - only notify for messages after this time
        messageListenerStartTimes[conversationId] = Date()

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

                Task { @MainActor [weak self] in
                    guard let self else { return }
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
            let lastSenderId = data["lastSenderId"] as? String
            let unreadCount = data["unreadCount"] as? [String: Int] ?? [:]
            let groupName = data["groupName"] as? String
            let groupPictureURL = data["groupPictureURL"] as? String
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            let lastInteractionByUser = Self.parseTimestampDictionary(data["lastInteractionByUser"])

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
                    existing.lastSenderId = lastSenderId
                    existing.unreadCount = unreadCount
                    existing.groupName = groupName
                    existing.groupPictureURL = groupPictureURL
                    if !lastInteractionByUser.isEmpty {
                        existing.lastInteractionByUser = lastInteractionByUser
                    }
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
                        lastSenderId: lastSenderId,
                        unreadCount: unreadCount,
                        lastInteractionByUser: lastInteractionByUser,
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
                    messageListenerStartTimes.removeValue(forKey: conversationId)
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
                let statusRaw = data["deliveryState"] as? String
            else {
                continue
            }

            let messageId = change.document.documentID
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            let readReceipts = Self.parseReadReceipts(
                from: data,
                fallbackTimestamp: timestamp,
                defaultReader: senderId
            )
            let status = MessageDeliveryState(fromLegacy: statusRaw)

            // Determine final delivery state based on readReceipts
            let finalStatus: MessageDeliveryState = {
                // Keep failed and pending states as-is
                if status == .failed || status == .pending {
                    return status
                }

                // Check if any non-sender users have read the message
                let nonSenderReaders = readReceipts.keys.filter { $0 != senderId }

                if !nonSenderReaders.isEmpty {
                    // At least one recipient has read the message
                    return .read
                } else if !readReceipts.isEmpty && readReceipts.keys.contains(senderId) {
                    // Only sender has read receipt - check if message was delivered to others
                    // For now, if we're receiving it as a non-sender, mark as delivered
                    if let currentUserId, senderId != currentUserId {
                        return .delivered
                    }
                    return .sent
                } else {
                    // No read receipts, keep original status
                    return status
                }
            }()

            // Parse priority metadata
            let priorityScore = data["priorityScore"] as? Int
            let priorityLabel = data["priorityLabel"] as? String
            let priorityRationale = data["priorityRationale"] as? String
            let priorityAnalyzedAt = (data["priorityAnalyzedAt"] as? Timestamp)?.dateValue()

            // Parse scheduling intent metadata
            let schedulingIntent = data["schedulingIntent"] as? String
            let intentConfidence = data["intentConfidence"] as? Double
            let intentAnalyzedAt = (data["intentAnalyzedAt"] as? Timestamp)?.dateValue()
            let schedulingKeywords: [String] = {
                if let keywords = data["schedulingKeywords"] as? [String] {
                    return keywords
                }
                return []
            }()

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
                    existing.deliveryState = finalStatus
                    existing.readReceipts = readReceipts
                    existing.updatedAt = updatedAt
                    existing.priorityScore = priorityScore
                    existing.priorityLabel = priorityLabel
                    existing.priorityRationale = priorityRationale
                    existing.priorityAnalyzedAt = priorityAnalyzedAt
                    existing.schedulingIntent = schedulingIntent
                    existing.intentConfidence = intentConfidence
                    existing.intentAnalyzedAt = intentAnalyzedAt
                    existing.schedulingKeywords = schedulingKeywords
                } else {
                    let message = MessageEntity(
                        id: messageId,
                        conversationId: conversationId,
                        senderId: senderId,
                        text: text,
                        timestamp: timestamp,
                        deliveryState: finalStatus,
                        readReceipts: readReceipts,
                        updatedAt: updatedAt,
                        priorityScore: priorityScore,
                        priorityLabel: priorityLabel,
                        priorityRationale: priorityRationale,
                        priorityAnalyzedAt: priorityAnalyzedAt,
                        schedulingIntent: schedulingIntent,
                        intentConfidence: intentConfidence,
                        intentAnalyzedAt: intentAnalyzedAt,
                        schedulingKeywords: schedulingKeywords
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

        // Handle notifications for new messages
        // Only notify for messages that arrived after the listener was established
        let listenerStartTime = messageListenerStartTimes[conversationId] ?? .distantPast

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let messageId = change.document.documentID

            guard
                let senderId = data["senderId"] as? String,
                let text = data["text"] as? String,
                let currentUserId,
                change.type == .added,
                senderId != currentUserId
            else { continue }

            // Get message timestamp
            let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()

            // Only notify if message arrived after listener was established
            // This prevents duplicate notifications on app restart
            guard timestamp > listenerStartTime else { continue }

            // Trigger notification for new message
            if let notificationService {
                Task {
                    // Fetch sender name
                    let senderName = await fetchSenderName(senderId: senderId) ?? "Unknown"

                    await notificationService.handleNewMessage(
                        conversationId: conversationId,
                        senderName: senderName,
                        messagePreview: text,
                        isAppInForeground: isAppInForeground
                    )
                }
            }
        }

        // Mark messages as delivered
        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let senderId = data["senderId"] as? String,
                let statusRaw = data["deliveryState"] as? String,
                let currentUserId
            else { continue }

            if senderId != currentUserId, statusRaw == MessageDeliveryState.sent.rawValue {
                let messageId = change.document.documentID
                Task {
                    do {
                        let messageRef = db.collection("conversations")
                            .document(conversationId)
                            .collection("messages")
                            .document(messageId)
                        try await messageRef.setData([
                            "deliveryState": MessageDeliveryState.delivered.rawValue,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], merge: true)
                    } catch {
                        debugLog("Failed to mark message delivered: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func updateLocalSenderInteraction(conversationId: String, userId: String, timestamp: Date, lastMessage: String) async {
        guard let modelContext else { return }

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

    private func markMessageAsSent(messageId: String) async throws {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate<MessageEntity> { message in
                message.id == messageId
            }
        )
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.deliveryState = .sent
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
            message.deliveryState = .failed
            message.updatedAt = Date()
            try? modelContext.save()
        }

        pendingMessageTasks.removeValue(forKey: messageId)
    }

    /// Mark all unread messages in a conversation as read by the current user
    func markConversationMessagesAsRead(conversationId: String) async throws {
        guard let currentUserId else {
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
        }
    }

    /// Retry sending a failed message
    func retryFailedMessage(messageId: String) async throws {
        guard let modelContext, let currentUserId else {
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

        let payload: [String: Any] = [
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "text": message.text,
            "timestamp": Timestamp(date: message.timestamp),
            "deliveryState": MessageDeliveryState.sent.rawValue,
            // Legacy field for backward compatibility
            "deliveryStatus": "sent",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let task = Task { [weak self] in
            do {
                try await messageRef.setData(payload)
                try await self?.markMessageAsSent(messageId: messageId)
            } catch {
                await self?.markMessageAsFailed(messageId: messageId)
            }
        }

        pendingMessageTasks[messageId] = task
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
        lastSenderId: String?,
        unreadCount: [String: Int],
        lastInteractionByUser: [String: Date],
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
            existing.lastSenderId = lastSenderId
            existing.unreadCount = unreadCount
            if !lastInteractionByUser.isEmpty {
                existing.lastInteractionByUser = lastInteractionByUser
            }
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
                lastSenderId: lastSenderId,
                unreadCount: unreadCount,
                lastInteractionByUser: lastInteractionByUser,
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
        deliveryState: MessageDeliveryState,
        readReceipts: [String: Date]
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
            existing.deliveryState = deliveryState
            existing.readReceipts = readReceipts
            existing.updatedAt = timestamp
        } else {
            let message = MessageEntity(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                text: text,
                timestamp: timestamp,
                deliveryState: deliveryState,
                readReceipts: readReceipts,
                updatedAt: timestamp
            )
            modelContext.insert(message)
        }

        try modelContext.save()
    }

    private func fetchSenderName(senderId: String) async -> String? {
        guard let modelContext else { return nil }

        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == senderId
            }
        )
        descriptor.fetchLimit = 1

        if let user = try? modelContext.fetch(descriptor).first {
            return user.displayName
        }

        // If not found locally, try fetching from Firestore
        do {
            let userDoc = try await db.collection("users").document(senderId).getDocument()
            if let displayName = userDoc.data()?["displayName"] as? String {
                return displayName
            }
        } catch {
            debugLog("Failed to fetch sender name: \(error.localizedDescription)")
        }

        return nil
    }

    private func welcomeMessage(for botId: String) -> String {
        switch botId {
        case "dash-bot":
            return "Hey there! I'm Dash Bot, your quick and helpful assistant. Need help with questions, drafting messages, recommendations, or just a good conversation? I'm here for it. What can I do for you?"
        case "dad-bot":
            return "Well hello there! I'm Dad Bot. Whether you need a dad joke to brighten your day or some good ol' fatherly advice, I've got you covered. What's on your mind, kiddo?"
        default:
            return "Hi! I'm here to help. What can I do for you today?"
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MessagingService]", message)
        #endif
    }

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
