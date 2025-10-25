//
//  DeliveryStateTracker.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Tracks message delivery states and handles state transitions
@MainActor
final class DeliveryStateTracker {

    // MARK: - Properties

    private weak var modelContext: ModelContext?

    // MARK: - Initialization

    init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - State Transitions

    /// Mark a message as sent
    /// - Parameter messageId: The message to mark as sent
    /// - Throws: SwiftData errors
    func markAsSent(messageId: String) async throws {
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.id == messageId }
        )

        guard let message = try modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("[DeliveryStateTracker] Message not found: \(messageId)")
            #endif
            return
        }

        message.deliveryState = .sent
        message.updatedAt = Date()
        try modelContext.save()

        #if DEBUG
        print("[DeliveryStateTracker] Marked message as sent: \(messageId)")
        #endif
    }

    /// Mark a message as delivered
    /// - Parameter messageId: The message to mark as delivered
    /// - Throws: SwiftData errors
    func markAsDelivered(messageId: String) async throws {
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.id == messageId }
        )

        guard let message = try modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("[DeliveryStateTracker] Message not found: \(messageId)")
            #endif
            return
        }

        message.deliveryState = .delivered
        message.updatedAt = Date()
        try modelContext.save()

        #if DEBUG
        print("[DeliveryStateTracker] Marked message as delivered: \(messageId)")
        #endif
    }

    /// Mark a message as read
    /// - Parameter messageId: The message to mark as read
    /// - Throws: SwiftData errors
    func markAsRead(messageId: String) async throws {
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.id == messageId }
        )

        guard let message = try modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("[DeliveryStateTracker] Message not found: \(messageId)")
            #endif
            return
        }

        message.deliveryState = .read
        message.updatedAt = Date()
        try modelContext.save()

        #if DEBUG
        print("[DeliveryStateTracker] Marked message as read: \(messageId)")
        #endif
    }

    /// Mark a message as failed
    /// - Parameter messageId: The message to mark as failed
    /// - Throws: SwiftData errors
    func markAsFailed(messageId: String) async {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.id == messageId }
        )

        guard let message = try? modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("[DeliveryStateTracker] Message not found: \(messageId)")
            #endif
            return
        }

        message.deliveryState = .failed
        try? modelContext.save()

        #if DEBUG
        print("[DeliveryStateTracker] Marked message as failed: \(messageId)")
        #endif
    }

    /// Parse delivery state from Firestore data with backward compatibility
    /// - Parameters:
    ///   - data: Firestore document data
    ///   - fallback: Fallback state if none found
    /// - Returns: Parsed delivery state
    static func parseDeliveryState(
        from data: [String: Any],
        fallback: MessageDeliveryState = .sent
    ) -> MessageDeliveryState {
        // Try new field first
        if let stateRaw = data["deliveryState"] as? String {
            return MessageDeliveryState(fromLegacy: stateRaw)
        }
        // Fall back to legacy field
        if let statusRaw = data["deliveryStatus"] as? String {
            return MessageDeliveryState(fromLegacy: statusRaw)
        }
        return fallback
    }
}
