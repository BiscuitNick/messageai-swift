//
//  DebugView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 11/19/25.
//

import FirebaseAuth
import FirebaseCore
import SwiftUI

struct DebugView: View {
    let currentUser: AuthService.AppUser

    @Environment(AuthService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(MessagingService.self) private var messagingService

    private var firebaseOptions: FirebaseOptions? {
        FirebaseApp.app()?.options
    }

    private var messagingDebug: MessagingService.DebugSnapshot {
        messagingService.debugSnapshot
    }

    var body: some View {
        NavigationStack {
            List {
                firebaseSection
                authSection
                messagingSection
                notificationSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Debug")
        }
    }

    private var firebaseSection: some View {
        Section("Firebase App") {
            if let options = firebaseOptions {
                LabeledContent("Project ID", value: options.projectID ?? "Unavailable")
                LabeledContent("App ID", value: options.googleAppID)
                LabeledContent("API Key", value: options.apiKey ?? "Unavailable")
                LabeledContent("Database URL", value: options.databaseURL ?? "Unavailable")
                LabeledContent("Storage Bucket", value: options.storageBucket ?? "Unavailable")
            } else {
                Text("Firebase not configured.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authSection: some View {
        Section("Authentication") {
            LabeledContent("Current User", value: currentUser.displayName)
            LabeledContent("User ID", value: currentUser.id)
            LabeledContent("Email", value: currentUser.email)
            LabeledContent("Firebase UID", value: Auth.auth().currentUser?.uid ?? "Unavailable")
            LabeledContent("Email Verified", value: Auth.auth().currentUser?.isEmailVerified == true ? "Yes" : "No")
        }
    }

    private var messagingSection: some View {
        Section("Messaging Service") {
            LabeledContent("Configured", value: messagingDebug.isConfigured ? "Yes" : "No")
            LabeledContent("Active User ID", value: messagingDebug.currentUserId ?? "nil")
            LabeledContent("Conversation Listener", value: messagingDebug.conversationListenerActive ? "Active" : "Inactive")
            LabeledContent("Message Listeners", value: "\(messagingDebug.activeMessageListeners)")
            LabeledContent("Pending Message Tasks", value: "\(messagingDebug.pendingMessageTasks)")
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            LabeledContent(
                "Authorization",
                value: statusDescription(for: notificationService.authorizationStatus)
            )
            LabeledContent("FCM Token", value: notificationService.fcmToken ?? "Unavailable")
        }
    }

    private func statusDescription(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}
