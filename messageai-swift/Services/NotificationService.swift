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

        // Coordination Alert Categories
        let viewDashboardAction = UNNotificationAction(
            identifier: "VIEW_COORDINATION_DASHBOARD",
            title: "View Dashboard",
            options: [.foreground]
        )
        let dismissAlertAction = UNNotificationAction(
            identifier: "DISMISS_COORDINATION_ALERT",
            title: "Dismiss",
            options: [.destructive]
        )

        // Action Item Alert
        let actionItemCategory = UNNotificationCategory(
            identifier: "COORDINATION_ACTION_ITEM",
            actions: [viewDashboardAction, dismissAlertAction],
            intentIdentifiers: [],
            options: []
        )

        // Blocker Alert
        let blockerCategory = UNNotificationCategory(
            identifier: "COORDINATION_BLOCKER",
            actions: [viewDashboardAction, dismissAlertAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Stale Decision Alert
        let staleDecisionCategory = UNNotificationCategory(
            identifier: "COORDINATION_STALE_DECISION",
            actions: [viewDashboardAction, dismissAlertAction],
            intentIdentifiers: [],
            options: []
        )

        // Scheduling Conflict Alert
        let schedulingConflictCategory = UNNotificationCategory(
            identifier: "COORDINATION_SCHEDULING_CONFLICT",
            actions: [viewDashboardAction, dismissAlertAction],
            intentIdentifiers: [],
            options: []
        )

        // Upcoming Deadline Alert
        let deadlineCategory = UNNotificationCategory(
            identifier: "COORDINATION_DEADLINE",
            actions: [viewDashboardAction, dismissAlertAction],
            intentIdentifiers: [],
            options: []
        )

        // Register all categories
        center.setNotificationCategories([
            schedulingSuggestionCategory,
            actionItemCategory,
            blockerCategory,
            staleDecisionCategory,
            schedulingConflictCategory,
            deadlineCategory
        ])

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

    // MARK: - Coordination Alert Notifications

    /// Deduplication tracking for coordination alerts
    private var sentCoordinationAlerts: Set<String> = []

    /// Send a coordination alert notification
    /// - Parameters:
    ///   - alert: The proactive alert entity to notify about
    ///   - conversationId: The conversation this alert relates to
    ///   - conversationName: Display name of the conversation
    ///   - isAppInForeground: Whether app is currently active
    /// - Throws: Notification delivery errors
    func sendCoordinationAlertNotification(
        alert: ProactiveAlertEntity,
        conversationId: String,
        conversationName: String?,
        isAppInForeground: Bool
    ) async throws {
        // Deduplication - don't send the same alert twice
        if sentCoordinationAlerts.contains(alert.id) {
            #if DEBUG
            print("[NotificationService] Skipping duplicate coordination alert: \(alert.id)")
            #endif
            return
        }

        // Don't send if app is in foreground and conversation is active
        if isAppInForeground, activeConversationId == conversationId {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message

        // Select sound based on severity
        switch alert.severity {
        case .critical, .high:
            content.sound = .defaultCritical
        case .medium, .low:
            content.sound = .default
        }

        // Set category based on alert type
        let categoryIdentifier: String
        switch alert.alertType {
        case "action_item":
            categoryIdentifier = "COORDINATION_ACTION_ITEM"
        case "blocker":
            categoryIdentifier = "COORDINATION_BLOCKER"
        case "stale_decision":
            categoryIdentifier = "COORDINATION_STALE_DECISION"
        case "scheduling_conflict":
            categoryIdentifier = "COORDINATION_SCHEDULING_CONFLICT"
        case "upcoming_deadline":
            categoryIdentifier = "COORDINATION_DEADLINE"
        default:
            categoryIdentifier = "COORDINATION_ACTION_ITEM"
        }
        content.categoryIdentifier = categoryIdentifier

        // Include conversation info in user info
        content.userInfo = [
            "conversationId": conversationId,
            "alertId": alert.id,
            "alertType": alert.alertType,
            "type": "coordination_alert",
            "severity": alert.severity.rawValue,
            "conversationName": conversationName ?? "Unknown"
        ]

        // Create unique identifier
        let identifier = "coordination_alert_\(alert.id)"

        // Create request (immediate delivery)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try await UNUserNotificationCenter.current().add(request)

        // Mark as sent for deduplication
        sentCoordinationAlerts.insert(alert.id)

        #if DEBUG
        print("[NotificationService] Sent coordination alert notification: \(alert.alertType) - \(alert.title)")
        #endif
    }

    /// Batch send multiple coordination alerts with throttling
    /// - Parameters:
    ///   - alerts: Array of alerts to send
    ///   - conversationMap: Map of conversationId to conversation names
    ///   - isAppInForeground: Whether app is currently active
    /// - Throws: Notification delivery errors
    func sendCoordinationAlerts(
        _ alerts: [ProactiveAlertEntity],
        conversationMap: [String: String],
        isAppInForeground: Bool
    ) async throws {
        // Throttle to max 3 alerts per batch to avoid overwhelming user
        let maxAlertsPerBatch = 3

        // Sort by severity (critical/high first) and take top N
        let sortedAlerts = alerts.sorted { $0.severity.rawValue > $1.severity.rawValue }
        let alertsToSend = Array(sortedAlerts.prefix(maxAlertsPerBatch))

        for alert in alertsToSend {
            let conversationName = conversationMap[alert.conversationId]
            try await sendCoordinationAlertNotification(
                alert: alert,
                conversationId: alert.conversationId,
                conversationName: conversationName,
                isAppInForeground: isAppInForeground
            )

            // Small delay between notifications
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        #if DEBUG
        print("[NotificationService] Sent \(alertsToSend.count)/\(alerts.count) coordination alerts")
        #endif
    }

    /// Clear deduplication tracking (call when alerts are dismissed or read)
    /// - Parameter alertId: The alert ID to clear from tracking
    func clearCoordinationAlertTracking(for alertId: String) {
        sentCoordinationAlerts.remove(alertId)
    }

    /// Cancel a coordination alert notification
    /// - Parameter alertId: The alert whose notification should be cancelled
    func cancelCoordinationAlertNotification(for alertId: String) {
        let identifier = "coordination_alert_\(alertId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        sentCoordinationAlerts.remove(alertId)

        #if DEBUG
        print("[NotificationService] Cancelled coordination alert notification: \(alertId)")
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
            // Handle coordination alert actions
            if response.actionIdentifier == "VIEW_COORDINATION_DASHBOARD" {
                // Navigate to coordination dashboard
                NotificationCenter.default.post(
                    name: Notification.Name("OpenCoordinationDashboard"),
                    object: nil,
                    userInfo: userInfo
                )
            } else if response.actionIdentifier == "DISMISS_COORDINATION_ALERT" {
                // Dismiss the alert
                if let alertId = userInfo["alertId"] as? String, let service = self.aiFeaturesService {
                    do {
                        try service.dismissAlert(alertId)
                        self.clearCoordinationAlertTracking(for: alertId)
                        #if DEBUG
                        print("[NotificationService] Dismissed coordination alert: \(alertId)")
                        #endif
                    } catch {
                        print("[NotificationService] Failed to dismiss alert: \(error)")
                    }
                }
            } else if response.actionIdentifier == "VIEW_SCHEDULING_SUGGESTIONS" {
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
                // Default tap action - check notification type
                let notificationType = userInfo["type"] as? String

                if notificationType == "coordination_alert" {
                    // For coordination alerts, open the dashboard
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenCoordinationDashboard"),
                        object: nil,
                        userInfo: userInfo
                    )
                } else if let conversationId {
                    // For other notifications, navigate to conversation
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
