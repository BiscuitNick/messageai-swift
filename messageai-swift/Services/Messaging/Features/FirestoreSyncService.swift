//
//  FirestoreSyncService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for real-time Firestore synchronization
@MainActor
final class FirestoreSyncService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var currentUserId: String?
    private var isAppInForeground: Bool = true

    // Dependencies
    private var listenerManager: FirestoreListenerManager?
    private var conversationManager: ConversationManagementService?
    private var notificationService: NotificationCoordinator?

    // Message listener start times for notification filtering
    private var messageListenerStartTimes: [String: Date] = [:]

    // Callbacks
    var onMessageMutation: ((String, String) -> Void)?  // (conversationId, messageId)

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(
        modelContext: ModelContext,
        currentUserId: String,
        listenerManager: FirestoreListenerManager,
        conversationManager: ConversationManagementService,
        notificationService: NotificationCoordinator? = nil
    ) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
        self.listenerManager = listenerManager
        self.conversationManager = conversationManager
        self.notificationService = notificationService
        observeConversations(for: currentUserId)
    }

    func setAppInForeground(_ isInForeground: Bool) {
        self.isAppInForeground = isInForeground
    }

    func reset() {
        listenerManager?.removeAll()
        messageListenerStartTimes.removeAll()
        currentUserId = nil
        onMessageMutation = nil
    }

    // MARK: - Public API

    /// Ensure a message listener is active for a conversation
    /// - Parameter conversationId: The conversation ID
    func ensureMessageListener(for conversationId: String) {
        observeMessages(for: conversationId)
    }

    // MARK: - Observation

    /// Start observing conversations for a user
    private func observeConversations(for userId: String) {
        let listenerId = "conversations"
        listenerManager?.remove(id: listenerId)

        let listener = db.collection("conversations")
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

        listenerManager?.register(id: listenerId, listener: listener)
    }

    /// Start observing messages for a conversation
    func observeMessages(for conversationId: String) {
        let listenerId = "messages-\(conversationId)"

        // Remove existing listener if any
        if listenerManager?.isActive(id: listenerId) == true {
            listenerManager?.remove(id: listenerId)
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
                    await self.handleMessageSnapshot(
                        conversationId: conversationId,
                        snapshot: snapshot
                    )
                }
            }

        listenerManager?.register(id: listenerId, listener: listener)
    }

    // MARK: - Snapshot Handlers

    /// Handle conversation snapshot updates
    private func handleConversationSnapshot(_ snapshot: QuerySnapshot?) async {
        guard let snapshot, let modelContext = modelContext, let currentUserId = currentUserId else {
            return
        }

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
                let listenerId = "messages-\(conversationId)"
                listenerManager?.remove(id: listenerId)
                messageListenerStartTimes.removeValue(forKey: conversationId)
            }
        }

        do {
            try modelContext.save()
        } catch {
            debugLog("Failed to save conversations: \(error.localizedDescription)")
        }
    }

    /// Handle message snapshot updates
    private func handleMessageSnapshot(
        conversationId: String,
        snapshot: QuerySnapshot?
    ) async {
        guard let snapshot, let modelContext = modelContext else {
            #if DEBUG
            print("[FirestoreSyncService] handleMessageSnapshot: snapshot or modelContext is nil")
            #endif
            return
        }

        let isFromCache = snapshot.metadata.isFromCache
        let hasPendingWrites = snapshot.metadata.hasPendingWrites

        #if DEBUG
        print("[FirestoreSyncService] Received message snapshot for \(conversationId) with \(snapshot.documents.count) documents, \(snapshot.documentChanges.count) changes, isFromCache: \(isFromCache), hasPendingWrites: \(hasPendingWrites)")
        #endif

        // First pass: Update all messages
        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let senderId = data["senderId"] as? String,
                let text = data["text"] as? String
            else {
                #if DEBUG
                print("[FirestoreSyncService] Skipping message - missing required fields. Data keys: \(data.keys)")
                #endif
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

            // Check if this specific document has pending writes or is from cache
            let docIsFromCache = change.document.metadata.isFromCache
            let docHasPendingWrites = change.document.metadata.hasPendingWrites

            // Support deliveryState field (no legacy needed for new app)
            let hasDeliveryStateField = data["deliveryState"] != nil
            let statusRaw: String

            if let state = data["deliveryState"] as? String {
                // Trust the deliveryState from Firestore if it exists
                statusRaw = state
            } else if senderId == currentUserId {
                // Sender's own message WITHOUT deliveryState field
                // This means it's a new message that hasn't been written with state yet
                if docIsFromCache || docHasPendingWrites {
                    // Message from local cache (offline write) - keep pending
                    statusRaw = MessageDeliveryState.pending.rawValue
                } else {
                    // Message from server - mark as sent
                    statusRaw = MessageDeliveryState.sent.rawValue
                }
            } else {
                // Recipient receiving a message - default to sent
                statusRaw = MessageDeliveryState.sent.rawValue
            }

            let status = MessageDeliveryState(rawValue: statusRaw) ?? .sent

            // Determine final delivery state based on readReceipts
            let finalStatus: MessageDeliveryState = {
                // Keep failed and pending states as-is
                if status == .failed || status == .pending {
                    return status
                }

                // Only override to pending for cache IF there's no deliveryState field
                // If deliveryState field exists, trust it!
                if senderId == currentUserId && !hasDeliveryStateField && (docIsFromCache || docHasPendingWrites) {
                    return .pending
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
                    #if DEBUG
                    print("[FirestoreSyncService] Updating existing message: \(messageId), currentState: \(existing.deliveryState.rawValue), finalStatus: \(finalStatus.rawValue), docIsFromCache: \(docIsFromCache), docHasPendingWrites: \(docHasPendingWrites)")
                    #endif
                    existing.text = text
                    existing.timestamp = timestamp

                    // Update delivery state based on sync source
                    if senderId == currentUserId {
                        // Sender's own message
                        if existing.deliveryState == .pending {
                            // Message is currently pending locally
                            if !docIsFromCache && !docHasPendingWrites && hasDeliveryStateField {
                                // Message is from server, no pending writes, and has deliveryState field
                                // But it's still marked as pending - update it to sent!
                                if status == .pending {
                                    // Update Firestore to mark as sent (only once)
                                    #if DEBUG
                                    print("[FirestoreSyncService] ✅ Server confirmed, updating Firestore .pending → .sent")
                                    #endif
                                    existing.deliveryState = .sent

                                    // Update Firestore document (fire and forget)
                                    Task { [weak self] in
                                        let messageRef = self?.db.collection("conversations")
                                            .document(conversationId)
                                            .collection("messages")
                                            .document(messageId)
                                        try? await messageRef?.updateData([
                                            "deliveryState": MessageDeliveryState.sent.rawValue
                                        ])
                                    }
                                } else if finalStatus != .pending {
                                    // Already marked as sent in Firestore
                                    #if DEBUG
                                    print("[FirestoreSyncService] Updating local state to match server: \(finalStatus.rawValue)")
                                    #endif
                                    existing.deliveryState = finalStatus
                                }
                            } else {
                                // Still pending
                                #if DEBUG
                                print("[FirestoreSyncService] Keeping .pending state (cache: \(docIsFromCache), pending: \(docHasPendingWrites))")
                                #endif
                            }
                        } else if existing.deliveryState == .failed {
                            // Keep failed state unless explicitly changed
                            if finalStatus != .failed && finalStatus != .pending {
                                // Message was retried and succeeded
                                #if DEBUG
                                print("[FirestoreSyncService] Failed message now sent: \(finalStatus.rawValue)")
                                #endif
                                existing.deliveryState = finalStatus
                            }
                        } else {
                            // Already sent/delivered/read
                            // Only update if moving forward (sent -> delivered -> read)
                            // Never go backward (e.g., sent -> pending)
                            if finalStatus == .delivered && existing.deliveryState == .sent {
                                existing.deliveryState = .delivered
                                #if DEBUG
                                print("[FirestoreSyncService] Message delivered")
                                #endif
                            } else if finalStatus == .read && (existing.deliveryState == .sent || existing.deliveryState == .delivered) {
                                existing.deliveryState = .read
                                #if DEBUG
                                print("[FirestoreSyncService] Message read")
                                #endif
                            }
                        }
                    } else {
                        // Other user's message - update normally
                        if existing.deliveryState != finalStatus {
                            #if DEBUG
                            print("[FirestoreSyncService] Updated deliveryState to: \(finalStatus.rawValue)")
                            #endif
                            existing.deliveryState = finalStatus
                        }
                    }

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
                    // For sender's own messages from cache, always create as pending
                    let initialDeliveryState: MessageDeliveryState
                    if senderId == currentUserId && (docIsFromCache || docHasPendingWrites) {
                        initialDeliveryState = .pending
                        #if DEBUG
                        print("[FirestoreSyncService] Inserting new message (sender, cache: \(docIsFromCache), pending: \(docHasPendingWrites)): \(messageId), deliveryState: .pending")
                        #endif
                    } else {
                        initialDeliveryState = finalStatus
                        #if DEBUG
                        print("[FirestoreSyncService] Inserting new message: \(messageId) in conversation: \(conversationId), deliveryState: \(finalStatus.rawValue), isSender: \(senderId == currentUserId)")
                        #endif
                    }

                    let message = MessageEntity(
                        id: messageId,
                        conversationId: conversationId,
                        senderId: senderId,
                        text: text,
                        timestamp: timestamp,
                        deliveryState: initialDeliveryState,
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

        // Second pass: Handle notifications for new messages
        let listenerStartTime = messageListenerStartTimes[conversationId] ?? .distantPast

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let messageId = change.document.documentID

            guard
                let senderId = data["senderId"] as? String,
                let text = data["text"] as? String,
                let currentUserId = currentUserId,
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

        // Third pass: Mark messages as delivered
        for change in snapshot.documentChanges {
            let data = change.document.data()
            guard
                let senderId = data["senderId"] as? String,
                let currentUserId = currentUserId
            else { continue }

            // Support both old (deliveryStatus) and new (deliveryState) field names
            let statusRaw = (data["deliveryState"] as? String) ?? (data["deliveryStatus"] as? String)

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

    // MARK: - Private Helpers

    /// Fetch sender name from local or remote
    private func fetchSenderName(senderId: String) async -> String? {
        guard let modelContext = modelContext else { return nil }

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

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[FirestoreSyncService]", message)
        #endif
    }
}
