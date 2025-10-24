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
    private var aiFeaturesService: AIFeaturesService?

    func configure(aiFeaturesService: AIFeaturesService? = nil) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        self.aiFeaturesService = aiFeaturesService

        // Register notification categories
        registerNotificationCategories()
    }

    private func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()

        // Scheduling Suggestion Category
        let viewSuggestionsAction = UNNotificationAction(
            identifier: "VIEW_SCHEDULING_SUGGESTIONS",
            title: "View Suggestions",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_SCHEDULING_SUGGESTIONS",
            title: "Snooze 1h",
            options: []
        )
        let schedulingSuggestionCategory = UNNotificationCategory(
            identifier: "SCHEDULING_SUGGESTION",
            actions: [viewSuggestionsAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        // Register all categories
        center.setNotificationCategories([schedulingSuggestionCategory])

        #if DEBUG
        print("[NotificationService] Registered notification categories")
        #endif
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

    // MARK: - Scheduling Suggestion Notifications

    /// Send a notification prompting user to view scheduling suggestions
    /// - Parameters:
    ///   - conversationId: The conversation with scheduling intent
    ///   - confidence: Detection confidence score
    ///   - conversationName: Name of the conversation for display
    ///   - isAppInForeground: Whether app is currently in foreground
    /// - Throws: Notification scheduling errors
    func sendSchedulingSuggestionNotification(
        conversationId: String,
        confidence: Double,
        conversationName: String,
        isAppInForeground: Bool
    ) async throws {
        // Don't send if app is in foreground and conversation is active
        if isAppInForeground, activeConversationId == conversationId {
            return
        }

        // Check if suggestions are snoozed
        if let service = aiFeaturesService, service.isSchedulingSuggestionsSnoozed(for: conversationId) {
            #if DEBUG
            print("[NotificationService] Skipping notification - suggestions snoozed for \(conversationId)")
            #endif
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Meeting Time Detected"

        let confidenceText: String
        if confidence >= 0.8 {
            confidenceText = "High confidence"
        } else if confidence >= 0.6 {
            confidenceText = "Likely"
        } else {
            confidenceText = "Possible"
        }

        content.body = "\(confidenceText) scheduling intent in \(conversationName)"
        content.sound = .default
        content.categoryIdentifier = "SCHEDULING_SUGGESTION"
        content.userInfo = [
            "conversationId": conversationId,
            "type": "scheduling_suggestion",
            "confidence": confidence
        ]

        // Create unique identifier
        let identifier = "scheduling_suggestion_\(conversationId)"

        // Create request (immediate delivery)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try await UNUserNotificationCenter.current().add(request)

        #if DEBUG
        print("[NotificationService] Sent scheduling suggestion notification for \(conversationId)")
        #endif
    }

    /// Cancel a pending scheduling suggestion notification
    /// - Parameter conversationId: The conversation whose notification should be cancelled
    func cancelSchedulingSuggestionNotification(for conversationId: String) {
        let identifier = "scheduling_suggestion_\(conversationId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        #if DEBUG
        print("[NotificationService] Cancelled scheduling suggestion notification for \(conversationId)")
        #endif
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
        let userInfo = response.notification.request.content.userInfo
        let conversationId = userInfo["conversationId"] as? String

        Task { @MainActor in
            // Handle scheduling suggestion actions
            if response.actionIdentifier == "VIEW_SCHEDULING_SUGGESTIONS" {
                if let conversationId {
                    // Post notification to navigate to conversation and open suggestions
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenConversation"),
                        object: nil,
                        userInfo: [
                            "conversationId": conversationId,
                            "showSchedulingSuggestions": true
                        ]
                    )
                }
            } else if response.actionIdentifier == "SNOOZE_SCHEDULING_SUGGESTIONS" {
                if let conversationId, let service = self.aiFeaturesService {
                    do {
                        try service.snoozeSchedulingSuggestions(for: conversationId)
                        #if DEBUG
                        print("[NotificationService] Snoozed scheduling suggestions for \(conversationId)")
                        #endif
                    } catch {
                        print("[NotificationService] Failed to snooze: \(error)")
                    }
                }
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                // Default tap action - navigate to conversation
                if let conversationId {
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenConversation"),
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                }
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
