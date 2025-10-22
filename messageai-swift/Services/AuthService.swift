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
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
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
            if let userId {
                await setUserOffline(userId: userId)
            }
            return
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
        guard let modelContext else { return }

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

    private func setUserOffline(userId: String) async {
        guard let modelContext else { return }

        let targetId = userId
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == targetId
            }
        )
        descriptor.fetchLimit = 1

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.isOnline = false
                existing.lastSeen = Date()
                try modelContext.save()
            }
        } catch {
            errorMessage = "Failed to update user status: \(error.localizedDescription)"
        }

        if let service = firestoreService {
            do {
                try await service.updatePresence(userId: userId, isOnline: false)
            } catch {
                debugLog("Failed to update Firestore presence: \(error.localizedDescription)")
            }
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
