//
//  FirestoreService.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import Observation
import FirebaseFirestore

@MainActor
@Observable
final class FirestoreService {
    private let db: Firestore

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

    func updatePresence(userId: String, isOnline: Bool) async throws {
        let userRef = db.collection("users").document(userId)
        let data: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": Timestamp(date: Date()),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await userRef.setData(data, merge: true)
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
            update["readBy"] = FieldValue.arrayUnion([userId])
        }

        try await messageRef.setData(update, merge: true)
    }
}
