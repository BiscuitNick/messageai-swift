//
//  TypingStatusService.swift
//  messageai-swift
//
//  Created for Task 5 on 10/24/25.
//

import Foundation
import FirebaseFirestore
import Observation

@MainActor
@Observable
final class TypingStatusService {
    struct TypingIndicator: Identifiable {
        let id: String  // userId
        let userId: String
        let displayName: String
        let isTyping: Bool
        let lastUpdated: Date
        let expiresAt: Date

        var isExpired: Bool {
            Date() > expiresAt
        }
    }

    private let db: Firestore
    private var listeners: [String: ListenerRegistration] = [:]
    private var clearTasks: [String: Task<Void, Never>] = [:]
    private var currentUserId: String?

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(currentUserId: String) {
        self.currentUserId = currentUserId
    }

    /// Set typing status for current user in a conversation
    func setTyping(conversationId: String, isTyping: Bool) async throws {
        guard let currentUserId else {
            throw TypingError.notConfigured
        }

        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .document(currentUserId)

        if isTyping {
            // Set typing with 5-second expiration
            let expiresAt = Date().addingTimeInterval(5)

            try await typingRef.setData([
                "userId": currentUserId,
                "isTyping": true,
                "lastUpdated": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: expiresAt)
            ], merge: true)

            // Cancel any existing clear task
            clearTasks[conversationId]?.cancel()

            // Schedule auto-clear after 5 seconds
            let task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

                guard !Task.isCancelled else { return }

                try? await self?.setTyping(conversationId: conversationId, isTyping: false)
            }

            clearTasks[conversationId] = task
        } else {
            // Clear typing status
            try await typingRef.setData([
                "userId": currentUserId,
                "isTyping": false,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)

            // Cancel auto-clear task
            clearTasks[conversationId]?.cancel()
            clearTasks[conversationId] = nil
        }
    }

    /// Listen to typing indicators for a conversation
    func observeTypingStatus(conversationId: String, completion: @escaping ([TypingIndicator]) -> Void) {
        // Remove existing listener
        listeners[conversationId]?.remove()

        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")

        let listener = typingRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot else { return }

            let now = Date()
            var indicators: [TypingIndicator] = []

            for document in snapshot.documents {
                let data = document.data()
                let userId = data["userId"] as? String ?? document.documentID
                let isTyping = data["isTyping"] as? Bool ?? false
                let lastUpdated = (data["lastUpdated"] as? Timestamp)?.dateValue() ?? now
                let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue() ?? now

                // Only include if currently typing and not expired
                if isTyping && now <= expiresAt {
                    // Filter out current user
                    if userId != self.currentUserId {
                        indicators.append(TypingIndicator(
                            id: userId,
                            userId: userId,
                            displayName: userId, // Will be enriched with actual name in UI
                            isTyping: isTyping,
                            lastUpdated: lastUpdated,
                            expiresAt: expiresAt
                        ))
                    }
                }
            }

            Task { @MainActor in
                completion(indicators)
            }
        }

        listeners[conversationId] = listener
    }

    /// Stop observing typing status for a conversation
    func stopObserving(conversationId: String) {
        listeners[conversationId]?.remove()
        listeners.removeValue(forKey: conversationId)

        clearTasks[conversationId]?.cancel()
        clearTasks.removeValue(forKey: conversationId)
    }

    /// Cleanup all listeners and tasks
    func cleanup() {
        for (_, listener) in listeners {
            listener.remove()
        }
        listeners.removeAll()

        for (_, task) in clearTasks {
            task.cancel()
        }
        clearTasks.removeAll()
    }
}

enum TypingError: Error {
    case notConfigured
}
