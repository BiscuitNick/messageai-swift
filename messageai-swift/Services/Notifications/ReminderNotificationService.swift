//
//  ReminderNotificationService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import UserNotifications

/// Service responsible for reminder notifications (decisions and scheduling)
@MainActor
final class ReminderNotificationService {

    // MARK: - Properties

    private weak var aiCoordinator: AIFeaturesCoordinator?
    var activeConversationId: String?

    // MARK: - Configuration

    func configure(aiCoordinator: AIFeaturesCoordinator?) {
        self.aiCoordinator = aiCoordinator
    }

    func setActiveConversation(_ conversationId: String?) {
        self.activeConversationId = conversationId
    }

    // MARK: - Decision Reminders

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
        print("[ReminderNotificationService] Scheduled decision reminder for \(reminderDate)")
    }

    /// Cancel a scheduled decision reminder
    /// - Parameter decisionId: The decision whose reminder should be cancelled
    func cancelDecisionReminder(decisionId: String) {
        let identifier = "decision_reminder_\(decisionId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("[ReminderNotificationService] Cancelled decision reminder: \(decisionId)")
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

    // MARK: - Scheduling Suggestions

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
        if let service = aiCoordinator, service.schedulingService.isSchedulingSuggestionsSnoozed(for: conversationId) {
            #if DEBUG
            print("[ReminderNotificationService] Skipping notification - suggestions snoozed for \(conversationId)")
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
        print("[ReminderNotificationService] Sent scheduling suggestion notification for \(conversationId)")
        #endif
    }

    /// Cancel a pending scheduling suggestion notification
    /// - Parameter conversationId: The conversation whose notification should be cancelled
    func cancelSchedulingSuggestionNotification(for conversationId: String) {
        let identifier = "scheduling_suggestion_\(conversationId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        #if DEBUG
        print("[ReminderNotificationService] Cancelled scheduling suggestion notification for \(conversationId)")
        #endif
    }
}
