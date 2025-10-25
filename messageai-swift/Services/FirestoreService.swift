//
//  FirestoreService.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import Observation
import SwiftData
import FirebaseFirestore
import FirebaseFunctions

@MainActor
@Observable
final class FirestoreService {
    struct AgentMessage {
        let role: String
        let content: String
    }

    private let db: Firestore
    private let functions: Functions

    /// Internal accessor for Firestore database (for use by other services)
    var firestore: Firestore {
        db
    }
    @ObservationIgnored private var usersListener: ListenerRegistration?
    @ObservationIgnored private var userModelContext: ModelContext?
    @ObservationIgnored private var botsListener: ListenerRegistration?
    @ObservationIgnored private var botModelContext: ModelContext?
    @ObservationIgnored private var actionItemsListeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var actionItemsModelContexts: [String: ModelContext] = [:]
    @ObservationIgnored private var decisionsListeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var decisionsModelContexts: [String: ModelContext] = [:]

    init() {
        let firestore = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        firestore.settings = settings
        self.db = firestore
        self.functions = Functions.functions(region: "us-central1")
    }

    func upsertUser(_ user: AuthService.AppUser) async throws {
        let userRef = db.collection("users").document(user.id)
        let snapshot = try await userRef.getDocument()

        var data: [String: Any] = [
            "email": user.email,
            "displayName": user.displayName,
            "isOnline": true,
            "lastSeen": Timestamp(date: Date()),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let url = user.photoURL {
            data["profilePictureURL"] = url.absoluteString
        }

        if !snapshot.exists {
            data["createdAt"] = FieldValue.serverTimestamp()
        }

        try await userRef.setData(data, merge: true)
    }

    func updatePresence(userId: String, isOnline: Bool, lastSeen: Date = Date()) async throws {
        let userRef = db.collection("users").document(userId)
        let data: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": Timestamp(date: lastSeen),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await userRef.setData(data, merge: true)
    }

    func updateUserProfilePhoto(userId: String, photoURL: URL) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef.setData([
            "profilePictureURL": photoURL.absoluteString,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func startUserListener(modelContext: ModelContext) {
        if userModelContext !== modelContext {
            userModelContext = modelContext
        }

        usersListener?.remove()
        usersListener = db.collection("users")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("User listener error: \(error.localizedDescription)")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleUserSnapshot(snapshot, modelContext: modelContext)
                }
            }
    }

    func stopUserListener() {
        usersListener?.remove()
        usersListener = nil
        userModelContext = nil
    }

    func startBotListener(modelContext: ModelContext) {
        if botModelContext !== modelContext {
            botModelContext = modelContext
        }

        botsListener?.remove()
        botsListener = db.collection("bots")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Bot listener error: \(error.localizedDescription)")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleBotSnapshot(snapshot, modelContext: modelContext)
                }
            }
    }

    func stopBotListener() {
        botsListener?.remove()
        botsListener = nil
        botModelContext = nil
    }

    private func handleUserSnapshot(_ snapshot: QuerySnapshot?, modelContext: ModelContext) async {
        guard let snapshot else { return }

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let userId = change.document.documentID

            var descriptor = FetchDescriptor<UserEntity>(
                predicate: #Predicate<UserEntity> { user in
                    user.id == userId
                }
            )
            descriptor.fetchLimit = 1

            let email = data["email"] as? String ?? ""
            let displayName = data["displayName"] as? String ?? "MessageAI User"
            let profilePictureURL = data["profilePictureURL"] as? String
            let isOnline = data["isOnline"] as? Bool ?? false
            let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue() ?? Date()
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.email = email
                    existing.displayName = displayName
                    existing.profilePictureURL = profilePictureURL
                    existing.isOnline = isOnline
                    existing.lastSeen = lastSeen
                } else {
                    let newUser = UserEntity(
                        id: userId,
                        email: email,
                        displayName: displayName,
                        profilePictureURL: profilePictureURL,
                        isOnline: isOnline,
                        lastSeen: lastSeen,
                        createdAt: createdAt
                    )
                    modelContext.insert(newUser)
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
            debugLog("Failed to persist users: \(error.localizedDescription)")
        }
    }

    private func handleBotSnapshot(_ snapshot: QuerySnapshot?, modelContext: ModelContext) async {
        guard let snapshot else {
            debugLog("Bot snapshot is nil")
            return
        }

        debugLog("Bot snapshot received with \(snapshot.documentChanges.count) changes")

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let botId = change.document.documentID

            debugLog("Bot change type: \(change.type.rawValue) for botId: \(botId)")

            var descriptor = FetchDescriptor<BotEntity>(
                predicate: #Predicate<BotEntity> { bot in
                    bot.id == botId
                }
            )
            descriptor.fetchLimit = 1

            let name = data["name"] as? String ?? "AI Assistant"
            let description = data["description"] as? String ?? ""
            let avatarURL = data["avatarURL"] as? String ?? ""
            let category = data["category"] as? String ?? "general"
            let capabilities = data["capabilities"] as? [String] ?? []
            let model = data["model"] as? String ?? "gemini-1.5-flash"
            let systemPrompt = data["systemPrompt"] as? String ?? ""
            let tools = data["tools"] as? [String] ?? []
            let isActive = data["isActive"] as? Bool ?? true
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    debugLog("Updating existing bot: \(botId)")
                    existing.name = name
                    existing.botDescription = description
                    existing.avatarURL = avatarURL
                    existing.category = category
                    existing.capabilities = capabilities
                    existing.model = model
                    existing.systemPrompt = systemPrompt
                    existing.tools = tools
                    existing.isActive = isActive
                    existing.updatedAt = updatedAt
                } else {
                    debugLog("Creating new bot: \(botId) with name: \(name)")
                    let newBot = BotEntity(
                        id: botId,
                        name: name,
                        description: description,
                        avatarURL: avatarURL,
                        category: category,
                        capabilities: capabilities,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        isActive: isActive,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newBot)
                }
            case .removed:
                debugLog("Removing bot: \(botId)")
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        }

        do {
            try modelContext.save()
            debugLog("Bots persisted successfully")
        } catch {
            debugLog("Failed to persist bots: \(error.localizedDescription)")
        }
    }

    func startActionItemsListener(conversationId: String, modelContext: ModelContext) {
        actionItemsModelContexts[conversationId] = modelContext

        actionItemsListeners[conversationId]?.remove()
        actionItemsListeners[conversationId] = db.collection("conversations")
            .document(conversationId)
            .collection("actionItems")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Action items listener error: \(error.localizedDescription)")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleActionItemSnapshot(
                        snapshot,
                        conversationId: conversationId,
                        modelContext: modelContext
                    )
                }
            }
    }

    func stopActionItemsListener(conversationId: String) {
        actionItemsListeners[conversationId]?.remove()
        actionItemsListeners.removeValue(forKey: conversationId)
        actionItemsModelContexts.removeValue(forKey: conversationId)
    }

    func stopAllActionItemsListeners() {
        for (conversationId, _) in actionItemsListeners {
            stopActionItemsListener(conversationId: conversationId)
        }
    }

    private func handleActionItemSnapshot(
        _ snapshot: QuerySnapshot?,
        conversationId: String,
        modelContext: ModelContext
    ) async {
        guard let snapshot else { return }

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let actionItemId = change.document.documentID

            var descriptor = FetchDescriptor<ActionItemEntity>(
                predicate: #Predicate<ActionItemEntity> { item in
                    item.id == actionItemId
                }
            )
            descriptor.fetchLimit = 1

            let task = data["task"] as? String ?? ""
            let assignedTo = data["assignedTo"] as? String
            let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
            let priorityRaw = data["priority"] as? String ?? "medium"
            let statusRaw = data["status"] as? String ?? "pending"
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            let priority = ActionItemPriority(rawValue: priorityRaw) ?? .medium
            let status = ActionItemStatus(rawValue: statusRaw) ?? .pending

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.task = task
                    existing.assignedTo = assignedTo
                    existing.dueDate = dueDate
                    existing.priority = priority
                    existing.status = status
                    existing.updatedAt = updatedAt
                } else {
                    let newItem = ActionItemEntity(
                        id: actionItemId,
                        conversationId: conversationId,
                        task: task,
                        assignedTo: assignedTo,
                        dueDate: dueDate,
                        priority: priority,
                        status: status,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newItem)
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
            debugLog("Failed to persist action items: \(error.localizedDescription)")
        }
    }

    func startDecisionsListener(conversationId: String, modelContext: ModelContext) {
        decisionsModelContexts[conversationId] = modelContext

        debugLog("Starting decisions listener for conversation: \(conversationId)")

        decisionsListeners[conversationId]?.remove()
        decisionsListeners[conversationId] = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Decisions listener error: \(error.localizedDescription)")
                    return
                }

                self.debugLog("Decisions listener triggered with \(snapshot?.documents.count ?? 0) documents")

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleDecisionSnapshot(
                        snapshot,
                        conversationId: conversationId,
                        modelContext: modelContext
                    )
                }
            }
    }

    func stopDecisionsListener(conversationId: String) {
        decisionsListeners[conversationId]?.remove()
        decisionsListeners.removeValue(forKey: conversationId)
        decisionsModelContexts.removeValue(forKey: conversationId)
    }

    func stopAllDecisionsListeners() {
        for (conversationId, _) in decisionsListeners {
            stopDecisionsListener(conversationId: conversationId)
        }
    }

    private func handleDecisionSnapshot(
        _ snapshot: QuerySnapshot?,
        conversationId: String,
        modelContext: ModelContext
    ) async {
        guard let snapshot else { return }

        debugLog("Processing \(snapshot.documentChanges.count) decision changes")

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let decisionId = change.document.documentID

            debugLog("Decision change: \(change.type.rawValue) - ID: \(decisionId)")

            var descriptor = FetchDescriptor<DecisionEntity>(
                predicate: #Predicate<DecisionEntity> { decision in
                    decision.id == decisionId
                }
            )
            descriptor.fetchLimit = 1

            let decisionText = data["decisionText"] as? String ?? ""
            let contextSummary = data["contextSummary"] as? String ?? ""
            let participantIds = data["participantIds"] as? [String] ?? []
            let decidedAt = (data["decidedAt"] as? Timestamp)?.dateValue() ?? Date()
            let followUpStatusRaw = data["followUpStatus"] as? String ?? "pending"
            let confidenceScore = data["confidenceScore"] as? Double ?? 0.0
            let reminderDate = (data["reminderDate"] as? Timestamp)?.dateValue()
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            let followUpStatus = DecisionFollowUpStatus(rawValue: followUpStatusRaw) ?? .pending

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    debugLog("Updating existing decision: \(decisionId)")
                    existing.decisionText = decisionText
                    existing.contextSummary = contextSummary
                    existing.participantIds = participantIds
                    existing.decidedAt = decidedAt
                    existing.followUpStatus = followUpStatus
                    existing.confidenceScore = confidenceScore
                    existing.reminderDate = reminderDate
                    existing.updatedAt = updatedAt
                } else {
                    debugLog("Creating new decision: \(decisionId) - \(decisionText)")
                    let newDecision = DecisionEntity(
                        id: decisionId,
                        conversationId: conversationId,
                        decisionText: decisionText,
                        contextSummary: contextSummary,
                        participantIds: participantIds,
                        decidedAt: decidedAt,
                        followUpStatus: followUpStatus,
                        confidenceScore: confidenceScore,
                        reminderDate: reminderDate,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newDecision)
                }
            case .removed:
                if let existing = try? modelContext.fetch(descriptor).first {
                    debugLog("Removing decision: \(decisionId)")
                    modelContext.delete(existing)
                }
            }
        }

        do {
            try modelContext.save()
            debugLog("Successfully saved \(snapshot.documentChanges.count) decision changes to SwiftData")
        } catch {
            debugLog("Failed to persist decisions: \(error.localizedDescription)")
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[FirestoreService]", message)
        #endif
    }

    func markConversationRead(conversationId: String, userId: String) async throws {
        let conversationRef = db.collection("conversations").document(conversationId)
        try await conversationRef.setData([
            "unreadCount.\(userId)": 0,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updateMessageDelivery(conversationId: String, messageId: String, status: MessageDeliveryState, userId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        var update: [String: Any] = [
            "deliveryState": status.rawValue,
            // Legacy field for backward compatibility
            "deliveryStatus": status.rawValue == "pending" ? "sending" : status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if status == .read {
            update["readReceipts.\(userId)"] = FieldValue.serverTimestamp()
            update["readBy"] = FieldValue.arrayUnion([userId])
        }

        try await messageRef.setData(update, merge: true)
    }

    func chatWithAgent(messages: [AgentMessage], conversationId: String) async throws {
        let functions = Functions.functions(region: "us-central1")

        // Convert messages to format expected by Firebase function
        let messagesData = messages.map { message in
            return [
                "role": message.role,
                "content": message.content
            ]
        }

        let data: [String: Any] = [
            "messages": messagesData,
            "conversationId": conversationId
        ]

        do {
            _ = try await functions.httpsCallable("chatWithAgent").call(data)
            // Bot response is written directly to Firestore by the function
            // The listener will pick it up automatically
        } catch {
            throw error
        }
    }

    func ensureBotExists() async throws {
        debugLog("Creating bots via Firebase Function...")
        _ = try await functions.httpsCallable("createBots").call()
        debugLog("Bots created successfully")
    }

    func deleteBots() async throws {
        debugLog("Deleting bots via Firebase Function...")
        _ = try await functions.httpsCallable("deleteBots").call()
        debugLog("Bots deleted successfully")
    }

    // MARK: - Action Items Management

    /// Create a new action item in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this action item belongs to
    ///   - actionItemId: Unique identifier for the action item
    ///   - task: The task description
    ///   - priority: Task priority
    ///   - status: Task status
    ///   - assignedTo: Optional user assigned to this task
    ///   - dueDate: Optional due date
    /// - Throws: Firestore errors
    func createActionItem(
        conversationId: String,
        actionItemId: String,
        task: String,
        priority: ActionItemPriority,
        status: ActionItemStatus,
        assignedTo: String?,
        dueDate: Date?
    ) async throws {
        let actionItemRef = db.collection("conversations")
            .document(conversationId)
            .collection("actionItems")
            .document(actionItemId)

        var data: [String: Any] = [
            "task": task,
            "priority": priority.rawValue,
            "status": status.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let assignedTo = assignedTo {
            data["assignedTo"] = assignedTo
        }

        if let dueDate = dueDate {
            data["dueDate"] = Timestamp(date: dueDate)
        }

        try await actionItemRef.setData(data)
        debugLog("Created action item: \(actionItemId)")
    }

    /// Update an existing action item in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this action item belongs to
    ///   - actionItemId: The action item to update
    ///   - task: Updated task description
    ///   - priority: Updated priority
    ///   - status: Updated status
    ///   - assignedTo: Updated assignee (nil to remove)
    ///   - dueDate: Updated due date (nil to remove)
    /// - Throws: Firestore errors
    func updateActionItem(
        conversationId: String,
        actionItemId: String,
        task: String,
        priority: ActionItemPriority,
        status: ActionItemStatus,
        assignedTo: String?,
        dueDate: Date?
    ) async throws {
        let actionItemRef = db.collection("conversations")
            .document(conversationId)
            .collection("actionItems")
            .document(actionItemId)

        var data: [String: Any] = [
            "task": task,
            "priority": priority.rawValue,
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let assignedTo = assignedTo {
            data["assignedTo"] = assignedTo
        } else {
            data["assignedTo"] = FieldValue.delete()
        }

        if let dueDate = dueDate {
            data["dueDate"] = Timestamp(date: dueDate)
        } else {
            data["dueDate"] = FieldValue.delete()
        }

        try await actionItemRef.setData(data, merge: true)
        debugLog("Updated action item: \(actionItemId)")
    }

    /// Delete an action item from Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this action item belongs to
    ///   - actionItemId: The action item to delete
    /// - Throws: Firestore errors
    func deleteActionItem(conversationId: String, actionItemId: String) async throws {
        let actionItemRef = db.collection("conversations")
            .document(conversationId)
            .collection("actionItems")
            .document(actionItemId)

        try await actionItemRef.delete()
        debugLog("Deleted action item: \(actionItemId)")
    }

    // MARK: - Decisions Management

    /// Update a decision's follow-up status in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to update
    ///   - followUpStatus: New follow-up status
    /// - Throws: Firestore errors
    func updateDecisionStatus(
        conversationId: String,
        decisionId: String,
        followUpStatus: DecisionFollowUpStatus
    ) async throws {
        let decisionRef = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .document(decisionId)

        let data: [String: Any] = [
            "followUpStatus": followUpStatus.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await decisionRef.setData(data, merge: true)
        debugLog("Updated decision status: \(decisionId)")
    }

    /// Update a decision's reminder date in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to update
    ///   - reminderDate: New reminder date (nil to clear)
    /// - Throws: Firestore errors
    func updateDecisionReminder(
        conversationId: String,
        decisionId: String,
        reminderDate: Date?
    ) async throws {
        let decisionRef = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .document(decisionId)

        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let reminderDate = reminderDate {
            data["reminderDate"] = Timestamp(date: reminderDate)
        } else {
            data["reminderDate"] = FieldValue.delete()
        }

        try await decisionRef.setData(data, merge: true)
        debugLog("Updated decision reminder: \(decisionId)")
    }

    /// Create a new decision in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: Unique identifier for the decision
    ///   - decisionText: The decision text
    ///   - contextSummary: Context summary
    ///   - participantIds: Participant IDs
    ///   - decidedAt: When the decision was made
    ///   - followUpStatus: Follow-up status
    ///   - confidenceScore: Confidence score
    /// - Throws: Firestore errors
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
        let decisionRef = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .document(decisionId)

        let data: [String: Any] = [
            "decisionText": decisionText,
            "contextSummary": contextSummary,
            "participantIds": participantIds,
            "decidedAt": Timestamp(date: decidedAt),
            "followUpStatus": followUpStatus.rawValue,
            "confidenceScore": confidenceScore,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await decisionRef.setData(data)
        debugLog("Created decision: \(decisionId)")
    }

    /// Update a decision in Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to update
    ///   - decisionText: Updated decision text
    ///   - contextSummary: Updated context summary
    ///   - decidedAt: Updated decided at date
    ///   - followUpStatus: Updated follow-up status
    /// - Throws: Firestore errors
    func updateDecision(
        conversationId: String,
        decisionId: String,
        decisionText: String,
        contextSummary: String,
        decidedAt: Date,
        followUpStatus: DecisionFollowUpStatus
    ) async throws {
        let decisionRef = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .document(decisionId)

        let data: [String: Any] = [
            "decisionText": decisionText,
            "contextSummary": contextSummary,
            "decidedAt": Timestamp(date: decidedAt),
            "followUpStatus": followUpStatus.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await decisionRef.setData(data, merge: true)
        debugLog("Updated decision: \(decisionId)")
    }

    /// Delete a decision from Firestore
    /// - Parameters:
    ///   - conversationId: The conversation this decision belongs to
    ///   - decisionId: The decision to delete
    /// - Throws: Firestore errors
    func deleteDecision(conversationId: String, decisionId: String) async throws {
        let decisionRef = db.collection("conversations")
            .document(conversationId)
            .collection("decisions")
            .document(decisionId)

        try await decisionRef.delete()
        debugLog("Deleted decision: \(decisionId)")
    }
}
