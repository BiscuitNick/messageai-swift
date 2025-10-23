//
//  NotificationService.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import Observation
import UserNotifications
import FirebaseMessaging
import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class NotificationService: NSObject {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var fcmToken: String?
    var activeConversationId: String?

    private var hasRegisteredForRemotes = false

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    func setActiveConversation(_ conversationId: String?) {
        self.activeConversationId = conversationId
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = try await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus

            guard settings.authorizationStatus == .notDetermined else { return }

            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            print("[NotificationService] Authorization error: \(error.localizedDescription)")
        }
    }

    func registerForRemoteNotifications() async {
        guard authorizationStatus == .authorized else { return }
        guard !hasRegisteredForRemotes else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
            hasRegisteredForRemotes = true
        }
    }

    func handleDeviceToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    func handleNewMessage(
        conversationId: String,
        senderName: String,
        messagePreview: String,
        isAppInForeground: Bool
    ) async {
        // Don't show notification if conversation is currently active and app is in foreground
        if isAppInForeground, activeConversationId == conversationId {
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = messagePreview
        content.sound = .default
        content.badge = NSNumber(value: 1)
        content.userInfo = [
            "conversationId": conversationId,
            "type": "new_message"
        ]

        // Create unique identifier
        let identifier = UUID().uuidString

        // Create trigger (immediate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        // Add notification
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to show notification: \(error.localizedDescription)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        if let conversationId = userInfo["conversationId"] as? String {
            // Post notification to navigate to conversation
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: Notification.Name("OpenConversation"),
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
        }
        completionHandler()
    }
}

extension NotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
            print("[NotificationService] FCM token:", fcmToken ?? "nil")

            // Save FCM token to Firestore
            if let fcmToken, let userId = Auth.auth().currentUser?.uid {
                do {
                    try await Firestore.firestore()
                        .collection("users")
                        .document(userId)
                        .setData([
                            "fcmToken": fcmToken,
                            "updatedAt": FieldValue.serverTimestamp()
                        ], merge: true)
                    print("[NotificationService] FCM token saved to Firestore")
                } catch {
                    print("[NotificationService] Failed to save FCM token: \(error.localizedDescription)")
                }
            }
        }
    }
}
