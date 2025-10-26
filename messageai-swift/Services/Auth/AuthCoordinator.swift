//
//  AuthCoordinator.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import Observation
import SwiftData
import FirebaseAuth
import UIKit

/// Coordinator that composes all authentication services
@MainActor
@Observable
final class AuthCoordinator {

    // MARK: - Types

    typealias AppUser = AuthenticationService.AppUser

    // MARK: - Services

    let authenticationService: AuthenticationService
    let userProfileService: UserProfileService
    let presenceService: PresenceService

    // MARK: - Properties

    var currentUser: AppUser?
    var isLoading: Bool {
        authenticationService.isLoading
    }
    var errorMessage: String? {
        get {
            authenticationService.errorMessage ?? userProfileService.errorMessage
        }
        set {
            // Allow clearing errors
            if newValue == nil {
                authenticationService.errorMessage = nil
                userProfileService.errorMessage = nil
            }
        }
    }

    @ObservationIgnored private weak var firestoreCoordinator: FirestoreCoordinator?
    @ObservationIgnored private var lastKnownUserId: String?

    // MARK: - Initialization

    init() {
        self.authenticationService = AuthenticationService()
        self.userProfileService = UserProfileService()
        self.presenceService = PresenceService()

        // Set up auth state change handler
        authenticationService.onAuthStateChange = { [weak self] user in
            guard let self else { return }
            await self.handleAuthStateChange(user: user)
        }
    }

    // MARK: - Configuration

    func configure(modelContext: ModelContext, firestoreCoordinator: FirestoreCoordinator) {
        self.firestoreCoordinator = firestoreCoordinator
        userProfileService.configure(
            modelContext: modelContext,
            firestoreCoordinator: firestoreCoordinator
        )
        presenceService.configure(
            modelContext: modelContext,
            firestoreCoordinator: firestoreCoordinator
        )
    }

    // MARK: - Authentication

    /// Sign up with email and password
    func signUp(email: String, password: String, displayName: String) async {
        await authenticationService.signUp(email: email, password: password, displayName: displayName)
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        await authenticationService.signIn(email: email, password: password)
    }

    /// Sign out current user
    func signOut() {
        Task { @MainActor in
            await self.performSignOut()
        }
    }

    /// Sign in with Google
    func signInWithGoogle(presentingViewController: UIViewController) async {
        await authenticationService.signInWithGoogle(presentingViewController: presentingViewController)
    }

    // MARK: - Profile Management

    /// Update profile photo
    func updateProfilePhoto(with imageData: Data) async {
        guard let userId = currentUser?.id ?? lastKnownUserId else {
            userProfileService.errorMessage = "No authenticated user."
            return
        }

        if let updatedUser = await userProfileService.updateProfilePhoto(
            with: imageData,
            userId: userId,
            currentUser: currentUser
        ) {
            currentUser = updatedUser
            lastKnownUserId = updatedUser.id
        }
    }

    // MARK: - Presence Management

    /// Mark current user as online
    func markCurrentUserOnline() async {
        guard let userId = currentUser?.id ?? lastKnownUserId else { return }
        await presenceService.markUserOnline(userId: userId)
    }

    /// Mark current user as offline
    func markCurrentUserOffline() async {
        guard let userId = currentUser?.id ?? lastKnownUserId else { return }
        await presenceService.markUserOffline(userId: userId)
    }

    /// Handle scene becoming active
    func sceneDidBecomeActive() {
        let userId = currentUser?.id ?? lastKnownUserId
        presenceService.sceneDidBecomeActive(userId: userId)
    }

    /// Handle scene entering background
    func sceneDidEnterBackground() {
        let userId = currentUser?.id ?? lastKnownUserId
        presenceService.sceneDidEnterBackground(userId: userId)
    }

    // MARK: - Private Helpers

    private func performSignOut() async {
        let signingOutUserId = currentUser?.id ?? lastKnownUserId
        presenceService.cancelPresenceTasks()

        if let signingOutUserId {
            await presenceService.markUserOffline(userId: signingOutUserId)
        }

        await authenticationService.signOut()
        firestoreCoordinator?.stopUserListener()
    }

    private func handleAuthStateChange(user: FirebaseAuth.User?) async {
        guard let user else {
            let userId = currentUser?.id ?? lastKnownUserId
            currentUser = nil
            lastKnownUserId = nil
            firestoreCoordinator?.stopUserListener()
            presenceService.cancelPresenceTasks()
            if let userId {
                await presenceService.setUserOffline(userId: userId)
            }
            userProfileService.clearLocalData()
            return
        }

        let previousUserId = currentUser?.id ?? lastKnownUserId
        if let previousUserId, previousUserId != user.uid {
            userProfileService.clearLocalData()
        }

        let appUser = authenticationService.convertToAppUser(user)

        currentUser = appUser
        lastKnownUserId = appUser.id
        await userProfileService.persistUser(appUser)
        await presenceService.markUserOnline(userId: appUser.id)
        presenceService.startHeartbeat(userId: appUser.id)
    }
}
