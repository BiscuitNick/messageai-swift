//
//  ChatView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: ConversationEntity
    let currentUser: AuthService.AppUser
    private let conversationId: String
    private let participantIds: [String]

    @Environment(MessagingService.self) private var messagingService
    @Environment(AuthService.self) private var authService
    @Environment(NotificationService.self) private var notificationService

    @State private var messageText: String = ""
    @State private var sendError: String?
    @State private var isSending: Bool = false
    @FocusState private var composerFocused: Bool

    @Query private var participants: [UserEntity]
    @Query private var messages: [MessageEntity]

    private var participantLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
    }

    private var groupedMessages: [(date: Date, items: [MessageEntity])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return groups.keys.sorted().map { date in
            let items = groups[date]?.sorted(by: { $0.timestamp < $1.timestamp }) ?? []
            return (date: date, items: items)
        }
    }

    init(conversation: ConversationEntity, currentUser: AuthService.AppUser) {
        let conversationId = conversation.id
        let participantIds = conversation.participantIds

        self.conversation = conversation
        self.currentUser = currentUser
        self.conversationId = conversationId
        self.participantIds = participantIds
        _participants = Query(
            filter: #Predicate<UserEntity> { user in
                participantIds.contains(user.id)
            }
        )
        _messages = Query(
            filter: #Predicate<MessageEntity> { message in
                message.conversationId == conversationId
            },
            sort: [SortDescriptor(\MessageEntity.timestamp, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedMessages, id: \.date) { group in
                            Section {
                                ForEach(group.items) { message in
                                    MessageBubble(
                                        message: message,
                                        isCurrentUser: message.senderId == currentUser.id,
                                        currentUserId: currentUser.id,
                                        conversation: conversation,
                                        sender: participantLookup[message.senderId],
                                        participants: participants
                                    )
                                    .id(message.id)
                                }
                            } header: {
                                DateHeader(date: group.date)
                                    .padding(.vertical, 4)
                            }
                        }
                        Spacer().frame(height: 8)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .background(Color(.systemGroupedBackground))
                .onTapGesture {
                    // Track user interaction on tap
                    Task {
                        await messagingService.markConversationAsRead(conversationId)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5).onChanged { _ in
                        // Track user interaction on scroll
                        Task {
                            await messagingService.markConversationAsRead(conversationId)
                        }
                    }
                )
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        scrollToBottom(proxy: proxy)
                    }
                    Task {
                        await messagingService.markConversationAsRead(conversationId)
                    }
                }
                .task {
                    messagingService.ensureMessageListener(for: conversationId)
                    await messagingService.markConversationAsRead(conversationId)
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            ComposerView(
                messageText: $messageText,
                isSending: isSending,
                sendAction: sendMessage
            )
            .focused($composerFocused)
        }
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notificationService.setActiveConversation(conversationId)
        }
        .onDisappear {
            notificationService.setActiveConversation(nil)
        }
        .alert(
            "Unable to send message",
            isPresented: .init(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { sendError = nil }
            },
            message: {
                Text(sendError ?? "Unknown error")
            }
        )
    }

    private var chatTitle: String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }
        let others = participantIds.filter { $0 != currentUser.id }
        if let first = others.first,
           let user = participants.first(where: { $0.id == first }) {
            return user.displayName
        }
        return "Conversation"
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let content = text

        Task {
            isSending = true
            defer { isSending = false }
            do {
                try await messagingService.sendMessage(conversationId: conversationId, text: content)
                messageText = ""
            } catch {
                sendError = error.localizedDescription
            }
            if !composerFocused {
                composerFocused = true
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    let message: MessageEntity
    let isCurrentUser: Bool
    let currentUserId: String
    let conversation: ConversationEntity
    let sender: UserEntity?
    let participants: [UserEntity]
    @State private var showingReceiptDetails = false

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
                    isComplete = message.deliveryStatus != .sending
                    statusText = message.deliveryStatus == .sending ? "Sending" : "Sent"
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
                AvatarView(
                    initials: senderInitials,
                    profileURL: sender?.profilePictureURL,
                    status: sender?.presenceStatus ?? .offline
                )
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
        guard let name = sender?.displayName else { return "?" }
        return initials(from: name)
    }

    private var bubbleContent: some View {
        Text(message.text)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var metadataRow: some View {
        Button(action: { showingReceiptDetails.toggle() }) {
            HStack(spacing: 6) {
                Text(timestampText)
                    .foregroundStyle(timestampColor)
                    .font(.caption2)

                if message.deliveryStatus == .sending {
                    DeliveryStatusIcon(
                        status: message.deliveryStatus,
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

private struct DeliveryStatusIcon: View {
    let status: DeliveryStatus
    var color: Color

    var body: some View {
        if let iconName {
            Image(systemName: iconName)
                .foregroundStyle(color)
        }
    }

    private var iconName: String? {
        switch status {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        }
    }
}

private struct ReadStatusEntry: Identifiable {
    let id: String
    let displayName: String
    let initials: String
    let isSender: Bool
    let isSelf: Bool
    let isComplete: Bool
    let statusText: String
    let color: Color
}

private struct ReadStatusPopover: View {
    let entries: [ReadStatusEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.count > 1 {
                Text("Read Receipts")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(entry.color)
                            .opacity(entry.isComplete ? 1 : 0.2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.footnote.weight(.semibold))
                            Text(entry.statusText)
                                .font(.caption2)
                                .foregroundStyle(entry.isComplete ? .secondary : Color.secondary.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AvatarView: View {
    let initials: String
    let profileURL: String?
    let status: PresenceStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))

                if let profileURL,
                   let url = URL(string: profileURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            initialsView
                        case .empty:
                            ProgressView()
                                .tint(Color.accentColor)
                        @unknown default:
                            initialsView
                        }
                    }
                    .clipShape(Circle())
                } else {
                    initialsView
                }
            }
            .frame(width: 32, height: 32)

            Circle()
                .fill(status.indicatorColor.opacity(status == .offline ? 0.4 : 1))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 1)
                )
                .offset(x: 3, y: 3)
        }
    }

    private var initialsView: some View {
        Text(initials.isEmpty ? "?" : initials.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
    }
}

private struct DateHeader: View {
    let date: Date
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        Text(formatter.string(from: date))
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

private struct ComposerView: View {
    @Binding var messageText: String
    let isSending: Bool
    let sendAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button(action: sendAction) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
            }
            .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}
