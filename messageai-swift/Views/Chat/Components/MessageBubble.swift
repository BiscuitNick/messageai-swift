//
//  MessageBubble.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct MessageBubble: View {
    let message: MessageEntity
    let isCurrentUser: Bool
    let currentUserId: String
    let conversation: ConversationEntity
    let sender: UserEntity?
    let bot: BotEntity?
    let participants: [UserEntity]
    let isOnline: Bool
    let onRetryMessage: (() -> Void)?
    @State private var showingReceiptDetails = false

    private var displayName: String {
        if let bot {
            return bot.name
        }
        return sender?.displayName ?? "Unknown"
    }

    private var avatarURL: String? {
        if let bot {
            return bot.avatarURL
        }
        return sender?.profilePictureURL
    }

    private var presenceStatus: PresenceStatus {
        sender?.presenceStatus ?? .offline
    }

    private static let palette: [Color] = [
        Color(red: 0.17, green: 0.33, blue: 0.82),  // Blue
        Color(red: 0.12, green: 0.55, blue: 0.35),  // Green
        Color(red: 0.56, green: 0.17, blue: 0.68),  // Purple
        Color(red: 0.78, green: 0.20, blue: 0.20),  // Red
        Color(red: 0.94, green: 0.49, blue: 0.12),  // Orange
        Color(red: 0.95, green: 0.55, blue: 0.65),  // Pink
        Color(red: 0.20, green: 0.60, blue: 0.86),  // Light Blue
        Color(red: 0.45, green: 0.55, blue: 0.20)   // Olive
    ]

    private var participantLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
    }

    private var bubbleColor: Color {
        guard !isCurrentUser else { return Color.accentColor }
        let identifier = sender?.id ?? message.senderId
        return getConsistentColorForUser(identifier)
    }

    private var textColor: Color { Color.white }

    private var metaTextColor: Color {
        Color(.secondaryLabel)
    }

    private var timestampColor: Color {
        Color(.label)
    }

    private var timestampText: String {
        message.timestamp.formatted(date: .omitted, time: .shortened)
    }

    // All unique participant IDs sorted alphabetically (for consistent color assignment)
    // Sort by USER ID ONLY - not display name - for truly stable colors
    private var sortedAllParticipantIds: [String] {
        // Use only the stable participant list from the conversation
        let allIds = Set(conversation.participantIds)

        // Sort by USER ID directly - this NEVER changes
        return allIds.sorted { lhs, rhs in
            if lhs == currentUserId { return true }
            if rhs == currentUserId { return false }
            // Sort by actual ID string, not display name
            return lhs < rhs
        }
    }

    // For display order in checkmarks (sender first, then current user, then others)
    // This can include all participants including those in lastInteractionByUser
    private var orderedParticipantIds: [String] {
        var allIds = Set<String>()
        allIds.formUnion(conversation.participantIds)
        allIds.insert(message.senderId)
        allIds.insert(currentUserId)
        allIds.formUnion(conversation.lastInteractionByUser.keys)

        return allIds.sorted { lhs, rhs in
            if lhs == message.senderId { return true }
            if rhs == message.senderId { return false }
            if lhs == currentUserId { return true }
            if rhs == currentUserId { return false }
            // Sort by ID for stable ordering (display can use names separately)
            return lhs < rhs
        }
    }

    private func getConsistentColorForUser(_ userId: String) -> Color {
        if userId == currentUserId {
            return Color.accentColor
        }
        // Find position in sorted list (excluding current user for color assignment)
        let nonCurrentUserIds = sortedAllParticipantIds.filter { $0 != currentUserId }
        if let position = nonCurrentUserIds.firstIndex(of: userId) {
            let index = position % MessageBubble.palette.count
            return MessageBubble.palette[index]
        }
        // Fallback (shouldn't happen)
        return MessageBubble.palette[0]
    }

    private func hasSeen(_ userId: String) -> Bool {
        let userInteraction = conversation.lastInteractionByUser[userId] ?? .distantPast
        let messageTime = message.timestamp
        // Use >= to include exact matches (sender's own messages)
        return userInteraction >= messageTime
    }

    private var otherRecipientIds: [String] {
        orderedParticipantIds.filter { $0 != currentUserId && $0 != message.senderId }
    }

    private var seenRecipientCount: Int {
        otherRecipientIds.filter { hasSeen($0) }.count
    }

    private var totalRecipientCount: Int {
        otherRecipientIds.count
    }

    private var receiptEntries: [ReadStatusEntry] {
        orderedParticipantIds.map { userId in
            let user = participantLookup[userId]
            let isSender = userId == message.senderId
            let isSelf = userId == currentUserId

            let isComplete: Bool
            let statusText: String

            if isSender {
                // For the sender themselves viewing their own message
                if isSelf {
                    // Show complete only when message has hit server
                    isComplete = message.deliveryState != .pending
                    statusText = message.deliveryState == .pending ? "Sending" : "Sent"
                } else {
                    // For recipients viewing the sender's checkmark - always complete
                    // (they wouldn't see the message if it wasn't sent)
                    isComplete = true
                    statusText = "Sent"
                }
            } else {
                // For non-senders, check their interaction timestamp
                isComplete = hasSeen(userId)
                statusText = isComplete ? "Seen" : "Waiting"
            }

            let displayName: String
            if isSelf {
                displayName = "You"
            } else if let user {
                displayName = user.displayName
            } else {
                displayName = userId
            }

            return ReadStatusEntry(
                id: userId,
                displayName: displayName,
                initials: initials(for: userId),
                isSender: isSender,
                isSelf: isSelf,
                isComplete: isComplete,
                statusText: statusText,
                color: participantColor(for: userId, isSender: isSender, isSelf: isSelf)
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 40) }

            if !isCurrentUser {
                if let bot {
                    AvatarView(
                        bot: bot,
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                } else if let sender {
                    AvatarView(
                        user: sender,
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                } else {
                    AvatarView(
                        entity: .custom(initials: senderInitials, profileURL: avatarURL),
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                }
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                metadataRow
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)

            if isCurrentUser {
                Spacer(minLength: 8)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, isCurrentUser ? 0 : 4)
        .transition(.move(edge: isCurrentUser ? .trailing : .leading).combined(with: .opacity))
    }

    private var senderInitials: String {
        return initials(from: displayName)
    }

    private var bubbleContent: some View {
        Text(message.text)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if message.hasPriorityData && message.priority.sortOrder >= PriorityLevel.high.sortOrder {
                    Text(message.priority.emoji)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
    }

    private var metadataRow: some View {
        Button(action: { showingReceiptDetails.toggle() }) {
            HStack(spacing: 6) {
                Text(timestampText)
                    .foregroundStyle(timestampColor)
                    .font(.caption2)

                // Show delivery state indicator for sender's own messages
                if message.senderId == currentUserId {
                    DeliveryStateIcon(
                        state: message.deliveryState,
                        onRetry: message.deliveryState == .failed ? onRetryMessage : nil,
                        color: metaTextColor
                    )
                }

                ForEach(receiptEntries) { entry in
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(entry.color)
                        .opacity(entry.isComplete ? 1 : 0.2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingReceiptDetails, attachmentAnchor: .rect(.bounds), arrowEdge: isCurrentUser ? .trailing : .leading) {
            ReadStatusPopover(
                entries: receiptEntries
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func initials(for userId: String) -> String {
        if let user = participantLookup[userId] {
            return initials(from: user.displayName)
        }

        if userId == currentUserId {
            return "ME"
        }

        let cleaned = userId.replacingOccurrences(of: "-", with: " ")
        let fromId = initials(from: cleaned)
        if !fromId.isEmpty {
            return fromId
        }

        let fallback = String(userId.prefix(2)).uppercased()
        return fallback.isEmpty ? "?" : fallback
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        let combined = initials.prefix(2).joined()
        return combined.isEmpty ? "?" : combined
    }

    private func participantColor(for participantId: String, isSender: Bool, isSelf: Bool) -> Color {
        // Use the same consistent color assignment for all participants
        return getConsistentColorForUser(participantId)
    }
}
