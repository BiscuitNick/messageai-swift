//
//  DecisionsSyncService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Service responsible for decisions synchronization and management
@MainActor
final class DecisionsSyncService {

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

    /// Start observing decisions for a conversation
    /// - Parameters:
    ///   - conversationId: Conversation ID
    ///   - modelContext: SwiftData model context
    func startDecisionsListener(conversationId: String, modelContext: ModelContext) {
        modelContexts[conversationId] = modelContext

        debugLog("Starting decisions listener for conversation: \(conversationId)")

        let listenerId = "decisions-\(conversationId)"
        listenerManager?.remove(id: listenerId)

        let listener = db.collection("conversations")
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

        listenerManager?.register(id: listenerId, listener: listener)

        #if DEBUG
        print("[DecisionsService] Started listener for conversation: \(conversationId)")
        #endif
    }

    /// Stop observing decisions for a conversation
    /// - Parameter conversationId: Conversation ID
    func stopDecisionsListener(conversationId: String) {
        let listenerId = "decisions-\(conversationId)"
        listenerManager?.remove(id: listenerId)
        modelContexts.removeValue(forKey: conversationId)

        #if DEBUG
        print("[DecisionsService] Stopped listener for conversation: \(conversationId)")
        #endif
    }

    /// Stop all decisions listeners
    func stopAllDecisionsListeners() {
        for conversationId in modelContexts.keys {
            stopDecisionsListener(conversationId: conversationId)
        }
    }

    // MARK: - CRUD Operations

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

    // MARK: - Private Helpers

    /// Handle decision snapshot updates
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
        print("[DecisionsService]", message)
        #endif
    }
}
