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

    private func notificationSound(for priority: PriorityLevel, isAppInForeground: Bool) -> UNNotificationSound {
        // Use different sounds based on priority and app state
        switch priority {
        case .critical, .urgent:
            // Use default sound for urgent messages (always audible)
            return .default
        case .high:
            // Use default sound for high priority
            return .default
        case .medium, .low:
            // Use default sound for normal priority
            // Could use .defaultCritical for critical alerts requiring override
            return .default
        }
    }

    func handleNewMessage(
        conversationId: String,
        senderName: String,
        messagePreview: String,
        isAppInForeground: Bool,
        priority: PriorityLevel = .medium
    ) async {
        // Don't show notification if conversation is currently active and app is in foreground
        if isAppInForeground, activeConversationId == conversationId {
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = messagePreview

        // Select sound based on priority
        content.sound = notificationSound(for: priority, isAppInForeground: isAppInForeground)

        // Set category for interactive notifications based on priority
        if priority.sortOrder >= PriorityLevel.high.sortOrder {
            content.categoryIdentifier = "HIGH_PRIORITY_MESSAGE"
        } else {
            content.categoryIdentifier = "MESSAGE"
        }

        content.badge = NSNumber(value: 1)
        content.userInfo = [
            "conversationId": conversationId,
            "type": "new_message",
            "priority": priority.rawValue
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

    // MARK: - Decision Reminder Scheduling

    /// Schedule a reminder notification for a decision follow-up
    /// - Parameters:
    ///   - decisionId: Unique identifier for the decision
    ///   - conversationId: The conversation containing the decision
    ///   - decisionText: Brief text of the decision
    ///   - reminderDate: When to deliver the reminder
    /// - Throws: Notification scheduling errors
    func scheduleDecisionReminder(
        decisionId: String,
        conversationId: String,
        decisionText: String,
        reminderDate: Date
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Decision Follow-up"
        content.body = decisionText
        content.sound = .default
        content.categoryIdentifier = "DECISION_REMINDER"
        content.userInfo = [
            "conversationId": conversationId,
            "decisionId": decisionId,
            "type": "decision_reminder"
        ]

        // Create date-based trigger
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Use decisionId as identifier for easy cancellation
        let identifier = "decision_reminder_\(decisionId)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
        print("[NotificationService] Scheduled decision reminder for \(reminderDate)")
    }

    /// Cancel a scheduled decision reminder
    /// - Parameter decisionId: The decision whose reminder should be cancelled
    func cancelDecisionReminder(decisionId: String) {
        let identifier = "decision_reminder_\(decisionId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("[NotificationService] Cancelled decision reminder: \(decisionId)")
    }

    /// Reschedule a decision reminder to a new date
    /// - Parameters:
    ///   - decisionId: The decision to reschedule
    ///   - conversationId: The conversation containing the decision
    ///   - decisionText: Brief text of the decision
    ///   - newReminderDate: New date for the reminder
    /// - Throws: Notification scheduling errors
    func rescheduleDecisionReminder(
        decisionId: String,
        conversationId: String,
        decisionText: String,
        newReminderDate: Date
    ) async throws {
        // Cancel existing reminder
        cancelDecisionReminder(decisionId: decisionId)

        // Schedule new reminder
        try await scheduleDecisionReminder(
            decisionId: decisionId,
            conversationId: conversationId,
            decisionText: decisionText,
            reminderDate: newReminderDate
        )
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
