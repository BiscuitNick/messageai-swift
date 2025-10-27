//
//  AuthenticationService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// Service responsible for authentication operations
@MainActor
final class AuthenticationService {

    // MARK: - Types

    struct AppUser: Equatable, Identifiable {
        let id: String
        let email: String
        let displayName: String
        let photoURL: URL?
    }

    private enum Constants {
        static let defaultDisplayName = "MessageAI User"
    }

    // MARK: - Properties

    var isLoading: Bool = false
    var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // Callbacks
    var onAuthStateChange: ((FirebaseAuth.User?) async -> Void)?

    // MARK: - Initialization

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                await self.onAuthStateChange?(user)
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Public API

    /// Sign up with email and password
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

            await onAuthStateChange?(result.user)
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }

        isLoading = false
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await onAuthStateChange?(result.user)
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }

        isLoading = false
    }

    /// Sign out current user
    func signOut() async {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            errorMessage = nil
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }
    }

    /// Sign in with Google
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
            await onAuthStateChange?(authResult.user)
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

    /// Convert Firebase user to AppUser
    func convertToAppUser(_ user: FirebaseAuth.User) -> AppUser {
        AppUser(
            id: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? Constants.defaultDisplayName,
            photoURL: user.photoURL
        )
    }

    // MARK: - Private Helpers

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
}
