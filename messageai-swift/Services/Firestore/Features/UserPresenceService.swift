//
//  UserPresenceService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFirestore

/// Service responsible for managing user presence and profile data in Firestore
@MainActor
final class UserPresenceService {

    // MARK: - Properties

    private let db: Firestore

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    // MARK: - Public API

    /// Upsert a user to Firestore
    /// - Parameter user: The user to upsert
    /// - Throws: Firestore errors
    func upsertUser(_ user: AuthCoordinator.AppUser) async throws {
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

        #if DEBUG
        print("[UserPresenceService] Upserted user: \(user.id)")
        #endif
    }

    /// Update user presence status
    /// - Parameters:
    ///   - userId: User ID to update
    ///   - isOnline: Whether user is online
    ///   - lastSeen: Last seen timestamp
    /// - Throws: Firestore errors
    func updatePresence(userId: String, isOnline: Bool, lastSeen: Date = Date()) async throws {
        let userRef = db.collection("users").document(userId)
        let data: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": Timestamp(date: lastSeen),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await userRef.setData(data, merge: true)

        #if DEBUG
        print("[UserPresenceService] Updated presence for user: \(userId), online: \(isOnline)")
        #endif
    }

    /// Update user profile photo
    /// - Parameters:
    ///   - userId: User ID to update
    ///   - photoURL: New photo URL
    /// - Throws: Firestore errors
    func updateUserProfilePhoto(userId: String, photoURL: URL) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef.setData([
            "profilePictureURL": photoURL.absoluteString,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        #if DEBUG
        print("[UserPresenceService] Updated profile photo for user: \(userId)")
        #endif
    }
}
