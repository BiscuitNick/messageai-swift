//
//  ActionItemsSyncService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Service responsible for action items synchronization and management
@MainActor
final class ActionItemsSyncService {

    // MARK: - Properties

    private let db: Firestore
    private var listenerManager: FirestoreListenerManager?
    private var modelContexts: [String: ModelContext] = [:]

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(listenerManager: FirestoreListenerManager) {
        self.listenerManager = listenerManager
    }

    // MARK: - Listener Management

    /// Start observing action items for a conversation
    /// - Parameters:
    ///   - conversationId: Conversation ID
    ///   - modelContext: SwiftData model context
    func startActionItemsListener(conversationId: String, modelContext: ModelContext) {
        modelContexts[conversationId] = modelContext

        let listenerId = "actionItems-\(conversationId)"
        listenerManager?.remove(id: listenerId)

        let listener = db.collection("conversations")
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

        listenerManager?.register(id: listenerId, listener: listener)

        #if DEBUG
        print("[ActionItemsService] Started listener for conversation: \(conversationId)")
        #endif
    }

    /// Stop observing action items for a conversation
    /// - Parameter conversationId: Conversation ID
    func stopActionItemsListener(conversationId: String) {
        let listenerId = "actionItems-\(conversationId)"
        listenerManager?.remove(id: listenerId)
        modelContexts.removeValue(forKey: conversationId)

        #if DEBUG
        print("[ActionItemsService] Stopped listener for conversation: \(conversationId)")
        #endif
    }

    /// Stop all action items listeners
    func stopAllActionItemsListeners() {
        for conversationId in modelContexts.keys {
            stopActionItemsListener(conversationId: conversationId)
        }
    }

    // MARK: - CRUD Operations

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

    // MARK: - Private Helpers

    /// Handle action item snapshot updates
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

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ActionItemsService]", message)
        #endif
    }
}
