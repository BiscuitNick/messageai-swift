//
//  AlertNotificationService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import UserNotifications

/// Service responsible for coordination alert notifications
@MainActor
final class AlertNotificationService {

    // MARK: - Properties

    var activeConversationId: String?

    /// Deduplication tracking for coordination alerts
    private var sentCoordinationAlerts: Set<String> = []

    // MARK: - Public API

    func setActiveConversation(_ conversationId: String?) {
        self.activeConversationId = conversationId
    }

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
            print("[AlertNotificationService] Skipping duplicate coordination alert: \(alert.id)")
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
        print("[AlertNotificationService] Sent coordination alert notification: \(alert.alertType) - \(alert.title)")
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
        print("[AlertNotificationService] Sent \(alertsToSend.count)/\(alerts.count) coordination alerts")
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
        print("[AlertNotificationService] Cancelled coordination alert notification: \(alertId)")
        #endif
    }
}
