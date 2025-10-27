//
//  UserSyncService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Service responsible for real-time user synchronization from Firestore to SwiftData
@MainActor
final class UserSyncService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var listenerManager: FirestoreListenerManager?

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(listenerManager: FirestoreListenerManager) {
        self.listenerManager = listenerManager
    }

    // MARK: - Public API

    /// Start observing users collection
    /// - Parameter modelContext: SwiftData model context
    func startUserListener(modelContext: ModelContext) {
        self.modelContext = modelContext

        let listenerId = "users"
        listenerManager?.remove(id: listenerId)

        let listener = db.collection("users")
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

        listenerManager?.register(id: listenerId, listener: listener)

        #if DEBUG
        print("[UserSyncService] Started user listener")
        #endif
    }

    /// Stop observing users collection
    func stopUserListener() {
        listenerManager?.remove(id: "users")
        modelContext = nil

        #if DEBUG
        print("[UserSyncService] Stopped user listener")
        #endif
    }

    // MARK: - Private Helpers

    /// Handle user snapshot updates
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
        print("[UserSyncService]", message)
        #endif
    }
}
