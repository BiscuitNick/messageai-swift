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
                                        sender: participantLookup[message.senderId]
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
    let sender: UserEntity?

    private var bubbleColor: Color {
        isCurrentUser ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        isCurrentUser ? Color.white : Color.primary
    }

    private var statusText: String {
        switch message.deliveryStatus {
        case .sending:
            return "Sending"
        case .sent:
            return "Sent"
        case .delivered:
            return "Delivered"
        case .read:
            return "Read"
        }
    }

    private var timestampText: String {
        message.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 40) }

            if !isCurrentUser {
                AvatarView(
                    initials: senderInitials,
                    profileURL: sender?.profilePictureURL,
                    status: sender?.presenceStatus ?? .offline
                )
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 6) {
                    Text(timestampText)
                    if isCurrentUser {
                        DeliveryStatusIcon(status: message.deliveryStatus, isCurrentUser: true)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
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
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.prefix(2).joined()
    }
}

private struct DeliveryStatusIcon: View {
    let status: DeliveryStatus
    var isCurrentUser: Bool = false

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(Color.secondary)
    }

    private var iconName: String {
        switch status {
        case .sending:
            return "clock"
        case .sent:
            return "checkmark"
        case .delivered:
            return "checkmark.circle"
        case .read:
            return "checkmark.circle.fill"
        }
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
