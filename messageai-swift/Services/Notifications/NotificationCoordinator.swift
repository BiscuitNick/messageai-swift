//
//  NotificationCoordinator.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import Observation
import UserNotifications
import UIKit

/// Coordinator that composes all notification services
@MainActor
@Observable
final class NotificationCoordinator: NSObject {

    // MARK: - Services

    let permissionsService: NotificationPermissionsService
    let messageNotificationService: MessageNotificationService
    let reminderNotificationService: ReminderNotificationService
    let alertNotificationService: AlertNotificationService

    // MARK: - Properties

    private weak var aiCoordinator: AIFeaturesCoordinator?

    var authorizationStatus: UNAuthorizationStatus {
        permissionsService.authorizationStatus
    }

    var fcmToken: String? {
        permissionsService.fcmToken
    }

    // MARK: - Initialization

    override init() {
        self.permissionsService = NotificationPermissionsService()
        self.messageNotificationService = MessageNotificationService()
        self.reminderNotificationService = ReminderNotificationService()
        self.alertNotificationService = AlertNotificationService()

        super.init()

        // Set up delegates
        UNUserNotificationCenter.current().delegate = self
        permissionsService.configure()

        // Register notification categories
        registerNotificationCategories()
    }

    // MARK: - Configuration

    func configure(aiFeaturesService aiCoordinator: AIFeaturesCoordinator? = nil) {
        self.aiCoordinator = aiCoordinator
        reminderNotificationService.configure(aiCoordinator: aiCoordinator)
    }

    // MARK: - Category Registration

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
        print("[NotificationCoordinator] Registered notification categories")
        #endif
    }

    // MARK: - Active Conversation

    func setActiveConversation(_ conversationId: String?) {
        messageNotificationService.setActiveConversation(conversationId)
        reminderNotificationService.setActiveConversation(conversationId)
        alertNotificationService.setActiveConversation(conversationId)
    }

    // MARK: - Permissions

    func requestAuthorization() async {
        await permissionsService.requestAuthorization()
    }

    func registerForRemoteNotifications() async {
        await permissionsService.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ token: Data) {
        permissionsService.handleDeviceToken(token)
    }

    // MARK: - Message Notifications

    func handleNewMessage(
        conversationId: String,
        senderName: String,
        messagePreview: String,
        isAppInForeground: Bool,
        priority: PriorityLevel = .medium
    ) async {
        await messageNotificationService.handleNewMessage(
            conversationId: conversationId,
            senderName: senderName,
            messagePreview: messagePreview,
            isAppInForeground: isAppInForeground,
            priority: priority
        )
    }

    // MARK: - Decision Reminders

    func scheduleDecisionReminder(
        decisionId: String,
        conversationId: String,
        decisionText: String,
        reminderDate: Date
    ) async throws {
        try await reminderNotificationService.scheduleDecisionReminder(
            decisionId: decisionId,
            conversationId: conversationId,
            decisionText: decisionText,
            reminderDate: reminderDate
        )
    }

    func cancelDecisionReminder(decisionId: String) {
        reminderNotificationService.cancelDecisionReminder(decisionId: decisionId)
    }

    func rescheduleDecisionReminder(
        decisionId: String,
        conversationId: String,
        decisionText: String,
        newReminderDate: Date
    ) async throws {
        try await reminderNotificationService.rescheduleDecisionReminder(
            decisionId: decisionId,
            conversationId: conversationId,
            decisionText: decisionText,
            newReminderDate: newReminderDate
        )
    }

    // MARK: - Scheduling Suggestions

    func sendSchedulingSuggestionNotification(
        conversationId: String,
        confidence: Double,
        conversationName: String,
        isAppInForeground: Bool
    ) async throws {
        try await reminderNotificationService.sendSchedulingSuggestionNotification(
            conversationId: conversationId,
            confidence: confidence,
            conversationName: conversationName,
            isAppInForeground: isAppInForeground
        )
    }

    func cancelSchedulingSuggestionNotification(for conversationId: String) {
        reminderNotificationService.cancelSchedulingSuggestionNotification(for: conversationId)
    }

    // MARK: - Coordination Alerts

    func sendCoordinationAlertNotification(
        alert: ProactiveAlertEntity,
        conversationId: String,
        conversationName: String?,
        isAppInForeground: Bool
    ) async throws {
        try await alertNotificationService.sendCoordinationAlertNotification(
            alert: alert,
            conversationId: conversationId,
            conversationName: conversationName,
            isAppInForeground: isAppInForeground
        )
    }

    func sendCoordinationAlerts(
        _ alerts: [ProactiveAlertEntity],
        conversationMap: [String: String],
        isAppInForeground: Bool
    ) async throws {
        try await alertNotificationService.sendCoordinationAlerts(
            alerts,
            conversationMap: conversationMap,
            isAppInForeground: isAppInForeground
        )
    }

    func clearCoordinationAlertTracking(for alertId: String) {
        alertNotificationService.clearCoordinationAlertTracking(for: alertId)
    }

    func cancelCoordinationAlertNotification(for alertId: String) {
        alertNotificationService.cancelCoordinationAlertNotification(for: alertId)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationCoordinator: UNUserNotificationCenterDelegate {
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

        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler()
                return
            }

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
                if let alertId = userInfo["alertId"] as? String, let service = self.aiCoordinator {
                    do {
                        try service.coordinationInsightsService.dismissAlert(alertId)
                        self.clearCoordinationAlertTracking(for: alertId)
                        #if DEBUG
                        print("[NotificationCoordinator] Dismissed coordination alert: \(alertId)")
                        #endif
                    } catch {
                        print("[NotificationCoordinator] Failed to dismiss alert: \(error)")
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
                if let conversationId, let service = self.aiCoordinator {
                    do {
                        try service.schedulingService.snoozeSuggestions(for: conversationId)
                        #if DEBUG
                        print("[NotificationCoordinator] Snoozed scheduling suggestions for \(conversationId)")
                        #endif
                    } catch {
                        print("[NotificationCoordinator] Failed to snooze: \(error)")
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

            completionHandler()
        }
    }
}
