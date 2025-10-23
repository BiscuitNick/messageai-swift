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
    @ObservationIgnored private var usersListener: ListenerRegistration?
    @ObservationIgnored private var userModelContext: ModelContext?

    init() {
        let firestore = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        firestore.settings = settings
        self.db = firestore
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
                Task { @MainActor in
                    await self.handleUserSnapshot(snapshot, modelContext: modelContext)
                }
            }
    }

    func stopUserListener() {
        usersListener?.remove()
        usersListener = nil
        userModelContext = nil
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

    func updateMessageDelivery(conversationId: String, messageId: String, status: DeliveryStatus, userId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        var update: [String: Any] = [
            "deliveryStatus": status.rawValue,
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

    func ensureBotUserExists() async throws {
        let botUserId = "messageai-bot"
        let userRef = db.collection("users").document(botUserId)
        let snapshot = try await userRef.getDocument()

        if !snapshot.exists {
            let data: [String: Any] = [
                "email": "bot@messageai.app",
                "displayName": "AI Assistant",
                "profilePictureURL": "https://dpj39bucz99gb.cloudfront.net/n8qq1sycd9rg80ct1zbrfw5k58",
                "isOnline": true,
                "lastSeen": Timestamp(date: Date()),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await userRef.setData(data)
        }
    }
}
