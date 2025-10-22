//
//  AuthService.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import Observation
import SwiftData
import FirebaseAuth
import FirebaseCore
import FirebaseStorage
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class AuthService {
    struct AppUser: Equatable, Identifiable {
        let id: String
        let email: String
        let displayName: String
        let photoURL: URL?
    }

    private enum Constants {
        static let defaultDisplayName = "MessageAI User"
    }

    var currentUser: AppUser?
    var isLoading: Bool = false
    var errorMessage: String?

    @ObservationIgnored private var authStateHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var firestoreService: FirestoreService?
    @ObservationIgnored private var lastKnownUserId: String?
    @ObservationIgnored private var lastActivityTimestamp: Date = Date()
    @ObservationIgnored private var presenceHeartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var offlineTimerTask: Task<Void, Never>?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                await self.handleAuthStateChange(user: user)
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func configure(modelContext: ModelContext, firestoreService: FirestoreService) {
        if self.modelContext !== modelContext {
            self.modelContext = modelContext
        }
        self.firestoreService = firestoreService
    }

    func signUp(email: String, password: String, displayName: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Constants.defaultDisplayName
                : displayName
            try await changeRequest.commitChanges()

            await handleAuthStateChange(user: result.user)
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }

        isLoading = false
    }

    func signIn(email: String, password: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await handleAuthStateChange(user: result.user)
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }

        isLoading = false
    }

    func signOut() {
        do {
            let signingOutUserId = currentUser?.id ?? lastKnownUserId
            cancelPresenceTasks()
            if let signingOutUserId {
                Task { await self.markUserOffline(userId: signingOutUserId) }
            }
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            firestoreService?.stopUserListener()
            errorMessage = nil
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }
    }

    private func handleAuthStateChange(user: FirebaseAuth.User?) async {
        guard let user else {
            let userId = currentUser?.id ?? lastKnownUserId
            currentUser = nil
            lastKnownUserId = nil
            firestoreService?.stopUserListener()
            cancelPresenceTasks()
            if let userId {
                await setUserOffline(userId: userId)
            }
            clearLocalData()
            return
        }

        let previousUserId = currentUser?.id ?? lastKnownUserId
        if let previousUserId, previousUserId != user.uid {
            clearLocalData()
        }

        let appUser = AppUser(
            id: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? Constants.defaultDisplayName,
            photoURL: user.photoURL
        )

        currentUser = appUser
        lastKnownUserId = appUser.id
        errorMessage = nil
        await persistUser(appUser)
        await markCurrentUserOnline()
        startHeartbeatIfNeeded()
    }

    func signInWithGoogle(presentingViewController: UIViewController) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Google client configuration. Verify GoogleService-Info.plist."
            return
        }

        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            guard
                let idToken = result.user.idToken?.tokenString
            else {
                errorMessage = "Unable to retrieve Google ID token."
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            await handleAuthStateChange(user: authResult.user)
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.google.GIDSignIn",
               nsError.code == -5 {
                // User cancelled; no error message needed.
                return
            }
            errorMessage = userFriendlyMessage(for: error)
        }
    }

    private func persistUser(_ appUser: AppUser) async {
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

        if let service = firestoreService {
            do {
                try await service.upsertUser(appUser)
            } catch {
                debugLog("Failed to sync user to Firestore: \(error.localizedDescription)")
            }
        }
    }

    func markCurrentUserOnline() async {
        guard let userId = currentUser?.id ?? lastKnownUserId else { return }
        let now = Date()
        lastActivityTimestamp = now
        await updatePresence(userId: userId, isOnline: true, lastSeenOverride: now)
    }

    func markCurrentUserOffline() async {
        guard let userId = currentUser?.id ?? lastKnownUserId else { return }
        await markUserOffline(userId: userId)
    }

    private func markUserOffline(userId: String, lastSeenOverride: Date? = nil) async {
        let timestamp = lastSeenOverride ?? Date()
        lastActivityTimestamp = timestamp
        await updatePresence(userId: userId, isOnline: false, lastSeenOverride: timestamp)
    }

    private func setUserOffline(userId: String) async {
        guard let modelContext = modelContext else { return }

        let targetId = userId
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == targetId
            }
        )
        descriptor.fetchLimit = 1

        let now = Date()
        lastActivityTimestamp = now
        await updatePresence(userId: userId, isOnline: false, descriptor: descriptor, lastSeenOverride: now)
    }

    private func clearLocalData() {
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

    private func deleteAll<T: PersistentModel>(from context: ModelContext, entity: T.Type) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.includePendingChanges = true
        let items = try context.fetch(descriptor)
        items.forEach { context.delete($0) }
    }

    private func updatePresence(
        userId: String,
        isOnline: Bool,
        descriptor: FetchDescriptor<UserEntity>? = nil,
        lastSeenOverride: Date? = nil
    ) async {
        guard let modelContext = modelContext else { return }

        let fetchDescriptor: FetchDescriptor<UserEntity>
        if let descriptor {
            fetchDescriptor = descriptor
        } else {
            var temp = FetchDescriptor<UserEntity>(
                predicate: #Predicate<UserEntity> { user in
                    user.id == userId
                }
            )
            temp.fetchLimit = 1
            fetchDescriptor = temp
        }

        let timestamp = lastSeenOverride ?? Date()

        do {
            if let existing = try modelContext.fetch(fetchDescriptor).first {
                existing.isOnline = isOnline
                existing.lastSeen = timestamp
                try modelContext.save()
            }
        } catch {
            debugLog("Failed to update local presence: \(error.localizedDescription)")
        }

        guard let service = firestoreService else { return }

        do {
            try await service.updatePresence(userId: userId, isOnline: isOnline, lastSeen: timestamp)
        } catch {
            debugLog("Failed to update Firestore presence: \(error.localizedDescription)")
        }
    }

    func sceneDidBecomeActive() {
        cancelOfflineTimer()
        startHeartbeatIfNeeded()
        Task { await self.markCurrentUserOnline() }
    }

    func sceneDidEnterBackground() {
        stopHeartbeat()
        guard currentUser != nil || lastKnownUserId != nil else {
            cancelOfflineTimer()
            return
        }
        lastActivityTimestamp = Date()
        scheduleOfflineTimer()
    }

    private func startHeartbeatIfNeeded() {
        guard presenceHeartbeatTask == nil else { return }
        guard currentUser != nil || lastKnownUserId != nil else { return }
        presenceHeartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.markCurrentUserOnline()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func stopHeartbeat() {
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = nil
    }

    private func scheduleOfflineTimer() {
        cancelOfflineTimer()
        let reference = lastActivityTimestamp
        offlineTimerTask = Task { [weak self] in
            guard let self else { return }
            guard let userId = self.currentUser?.id ?? self.lastKnownUserId else { return }
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            await self.markUserOffline(userId: userId, lastSeenOverride: reference)
        }
    }

    private func cancelOfflineTimer() {
        offlineTimerTask?.cancel()
        offlineTimerTask = nil
    }

    private func cancelPresenceTasks() {
        stopHeartbeat()
        cancelOfflineTimer()
    }

    func updateProfilePhoto(with imageData: Data) async {
        errorMessage = nil
        guard let userId = currentUser?.id ?? lastKnownUserId else {
            errorMessage = "No authenticated user."
            return
        }

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
                displayName: currentUser?.displayName ?? Constants.defaultDisplayName,
                photoURL: downloadURL
            )

            currentUser = updatedUser
            lastKnownUserId = updatedUser.id

            await updateLocalUserPhoto(userId: userId, photoURL: downloadURL)

            if let service = firestoreService {
                do {
                    try await service.updateUserProfilePhoto(userId: userId, photoURL: downloadURL)
                } catch {
                    debugLog("Failed to sync profile photo: \(error.localizedDescription)")
                }
            }
        } catch {
            errorMessage = "Failed to update photo: \(error.localizedDescription)"
        }
    }

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

    private func userFriendlyMessage(for error: Error) -> String {
        if let authError = error as NSError?,
           let code = AuthErrorCode(rawValue: authError.code) {
            switch code {
            case .invalidEmail:
                return "The email address is invalid. Please check and try again."
            case .emailAlreadyInUse:
                return "An account already exists for this email."
            case .weakPassword:
                return "Password is too weak. Try a stronger one."
            case .wrongPassword:
                return "Incorrect password. Please try again."
            case .userNotFound:
                return "No account found with this email."
            case .networkError:
                return "Network error. Check your connection and retry."
            default:
                break
            }
        }

        return "Something went wrong. \(error.localizedDescription)"
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AuthService]", message)
        #endif
    }
}
