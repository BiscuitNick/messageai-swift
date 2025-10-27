//
//  MessageNotificationService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import UserNotifications

/// Service responsible for message notifications
@MainActor
final class MessageNotificationService {

    // MARK: - Properties

    var activeConversationId: String?

    // MARK: - Public API

    func setActiveConversation(_ conversationId: String?) {
        self.activeConversationId = conversationId
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
            print("[MessageNotificationService] Failed to show notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

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
}
