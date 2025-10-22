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

@MainActor
@Observable
final class NotificationService: NSObject {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var fcmToken: String?

    private var hasRegisteredForRemotes = false

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
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
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

extension NotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
            print("[NotificationService] FCM token:", fcmToken ?? "nil")
        }
    }
}
