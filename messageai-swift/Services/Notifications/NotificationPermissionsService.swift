//
//  NotificationPermissionsService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import UIKit

/// Service responsible for notification permissions and FCM token management
@MainActor
final class NotificationPermissionsService: NSObject {

    // MARK: - Properties

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var fcmToken: String?
    private var hasRegisteredForRemotes = false

    // MARK: - Authorization

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = try await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus

            guard settings.authorizationStatus == .notDetermined else { return }

            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            print("[NotificationPermissionsService] Authorization error: \(error.localizedDescription)")
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

    // MARK: - FCM Token Management

    func configure() {
        Messaging.messaging().delegate = self
    }
}

// MARK: - MessagingDelegate

extension NotificationPermissionsService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
            print("[NotificationPermissionsService] FCM token:", fcmToken ?? "nil")

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
                    print("[NotificationPermissionsService] FCM token saved to Firestore")
                } catch {
                    print("[NotificationPermissionsService] Failed to save FCM token: \(error.localizedDescription)")
                }
            }
        }
    }
}
