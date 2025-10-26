//
//  UserProfileService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseStorage

/// Service responsible for user profile management
@MainActor
final class UserProfileService {

    // MARK: - Types

    typealias AppUser = AuthenticationService.AppUser

    // MARK: - Properties

    private weak var modelContext: ModelContext?
    private weak var firestoreCoordinator: FirestoreCoordinator?

    var errorMessage: String?

    // MARK: - Configuration

    func configure(
        modelContext: ModelContext,
        firestoreCoordinator: FirestoreCoordinator
    ) {
        if self.modelContext !== modelContext {
            self.modelContext = modelContext
        }
        self.firestoreCoordinator = firestoreCoordinator
    }

    // MARK: - Public API

    /// Persist user to local storage and sync to Firestore
    func persistUser(_ appUser: AppUser) async {
        guard let modelContext = modelContext else { return }

        let targetId = appUser.id
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == targetId
            }
        )
        descriptor.fetchLimit = 1

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.email = appUser.email
                existing.displayName = appUser.displayName
                existing.profilePictureURL = appUser.photoURL?.absoluteString
                existing.isOnline = true
                existing.lastSeen = Date()
            } else {
                let newUser = UserEntity(
                    id: appUser.id,
                    email: appUser.email,
                    displayName: appUser.displayName,
                    profilePictureURL: appUser.photoURL?.absoluteString,
                    isOnline: true,
                    lastSeen: Date(),
                    createdAt: Date()
                )
                modelContext.insert(newUser)
            }

            try modelContext.save()
        } catch {
            errorMessage = "Failed to persist user locally: \(error.localizedDescription)"
            return
        }

        if let service = firestoreCoordinator {
            do {
                try await service.upsertUser(appUser)
            } catch {
                debugLog("Failed to sync user to Firestore: \(error.localizedDescription)")
            }
        }
    }

    /// Update profile photo
    func updateProfilePhoto(with imageData: Data, userId: String, currentUser: AppUser?) async -> AppUser? {
        errorMessage = nil

        do {
            let compressedData = imageData
            let storageRef = Storage.storage().reference()
                .child("profilePictures/\(userId).jpg")

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            _ = try await storageRef.putDataAsync(compressedData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()

            if let authUser = Auth.auth().currentUser {
                let changeRequest = authUser.createProfileChangeRequest()
                changeRequest.photoURL = downloadURL
                try await changeRequest.commitChanges()
            }

            let updatedUser = AppUser(
                id: userId,
                email: currentUser?.email ?? "",
                displayName: currentUser?.displayName ?? "MessageAI User",
                photoURL: downloadURL
            )

            await updateLocalUserPhoto(userId: userId, photoURL: downloadURL)

            if let service = firestoreCoordinator {
                do {
                    try await service.updateUserProfilePhoto(userId: userId, photoURL: downloadURL)
                } catch {
                    debugLog("Failed to sync profile photo: \(error.localizedDescription)")
                }
            }

            return updatedUser
        } catch {
            errorMessage = "Failed to update photo: \(error.localizedDescription)"
            return nil
        }
    }

    /// Clear all local data (called on sign out or user change)
    func clearLocalData() {
        guard let modelContext = modelContext else { return }

        do {
            try deleteAll(from: modelContext, entity: MessageEntity.self)
            try deleteAll(from: modelContext, entity: ConversationEntity.self)
            try deleteAll(from: modelContext, entity: UserEntity.self)
            try modelContext.save()
        } catch {
            debugLog("Failed to clear local data: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func updateLocalUserPhoto(userId: String, photoURL: URL) async {
        guard let modelContext = modelContext else { return }

        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == userId
            }
        )
        descriptor.fetchLimit = 1

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.profilePictureURL = photoURL.absoluteString
                try modelContext.save()
            }
        } catch {
            debugLog("Failed to update local profile photo: \(error.localizedDescription)")
        }
    }

    private func deleteAll<T: PersistentModel>(from context: ModelContext, entity: T.Type) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.includePendingChanges = true
        let items = try context.fetch(descriptor)
        items.forEach { context.delete($0) }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[UserProfileService]", message)
        #endif
    }
}
