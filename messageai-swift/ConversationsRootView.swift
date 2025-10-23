//
//  ConversationsRootView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import Foundation
import SwiftUI
import SwiftData

struct ConversationsRootView: View {
    let currentUser: AuthService.AppUser

    @Query(sort: [SortDescriptor(\ConversationEntity.updatedAt, order: .reverse)])
    private var conversations: [ConversationEntity]

    @Query private var users: [UserEntity]
    @Query private var bots: [BotEntity]

    @State private var isComposePresented = false
    @State private var selectedConversationID: String?
    @State private var searchText: String = ""

    private var selectableUsers: [UserEntity] {
        users.filter { $0.id != currentUser.id }
    }

    private var filteredConversations: [ConversationEntity] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversationTitle(for: conversation)
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredConversations.isEmpty {
                    if conversations.isEmpty {
                        EmptyStateView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGroupedBackground))
                    } else {
                        SearchEmptyView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGroupedBackground))
                    }
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            NavigationLink(
                                destination: ChatView(conversation: conversation, currentUser: currentUser),
                                tag: conversation.id,
                                selection: $selectedConversationID
                            ) {
                                ConversationRow(
                                    conversation: conversation,
                                    currentUser: currentUser,
                                    users: users,
                                    bots: bots
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .id(users.count) // Force refresh when users change
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposePresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(selectableUsers.isEmpty)
                }
            }
        }
        .sheet(isPresented: $isComposePresented) {
            NewConversationSheet(
                currentUser: currentUser,
                availableUsers: selectableUsers
            ) { conversationId in
                selectedConversationID = conversationId
                isComposePresented = false
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
    }

    private func conversationTitle(for conversation: ConversationEntity) -> String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }
        let userLookup = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        let botLookup = Dictionary(uniqueKeysWithValues: bots.map { ($0.id, $0) })
        let otherParticipant = conversation.participantIds.first { $0 != currentUser.id }

        guard let otherParticipant else { return "Conversation" }

        // Check if it's a bot (format: "bot:botId")
        if otherParticipant.hasPrefix("bot:") {
            let botId = String(otherParticipant.dropFirst(4))
            if let bot = botLookup[botId] {
                return bot.name
            }
        } else if let user = userLookup[otherParticipant] {
            return user.displayName
        }

        return "Conversation"
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

}

private struct ConversationRow: View {
    let conversation: ConversationEntity
    let currentUser: AuthService.AppUser
    let users: [UserEntity]
    let bots: [BotEntity]

    private var userLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }

    private var botLookup: [String: BotEntity] {
        Dictionary(uniqueKeysWithValues: bots.map { ($0.id, $0) })
    }

    private var title: String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }

        let otherParticipant = conversation.participantIds
            .first(where: { $0 != currentUser.id })

        guard let otherParticipant else { return "Conversation" }

        // Check if it's a bot (format: "bot:botId")
        if otherParticipant.hasPrefix("bot:") {
            let botId = String(otherParticipant.dropFirst(4))
            if let bot = botLookup[botId] {
                return bot.name
            }
        } else if let user = userLookup[otherParticipant] {
            return user.displayName
        }

        return "Conversation"
    }

    private var subtitle: String {
        conversation.lastMessage ?? "No messages yet"
    }

    private var timestampText: String {
        let date = conversation.lastMessageTimestamp ?? conversation.updatedAt
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private var unreadCount: Int {
        conversation.unreadCount[currentUser.id] ?? 0
    }

    private var presenceStatus: PresenceStatus {
        let otherParticipants = conversation.participantIds.filter { $0 != currentUser.id }
        if conversation.isGroup {
            let statuses = otherParticipants.compactMap { userLookup[$0]?.presenceStatus }
            if statuses.contains(.online) {
                return .online
            } else if statuses.contains(.away) {
                return .away
            } else {
                return .offline
            }
        } else if let other = otherParticipants.first,
                  let user = userLookup[other] {
            return user.presenceStatus
        }
        return .offline
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarPlaceholderView(
                initials: initials(for: title),
                profileURL: avatarProfileURL,
                status: presenceStatus
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !conversation.isGroup {
                        PresenceStatusBadge(status: presenceStatus)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.prefix(2).joined()
    }

    private var avatarProfileURL: String? {
        guard !conversation.isGroup else { return nil }
        let otherParticipant = conversation.participantIds.first { $0 != currentUser.id }

        guard let otherParticipant else { return nil }

        // Check if it's a bot (format: "bot:botId")
        if otherParticipant.hasPrefix("bot:") {
            let botId = String(otherParticipant.dropFirst(4))
            if let bot = botLookup[botId], !bot.avatarURL.isEmpty {
                return bot.avatarURL
            }
        } else if let user = userLookup[otherParticipant],
                  let url = user.profilePictureURL,
                  !url.isEmpty {
            return url
        }

        return nil
    }
}

private struct AvatarPlaceholderView: View {
    let initials: String
    let profileURL: String?
    let status: PresenceStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
            Circle()
                .fill(status.indicatorColor.opacity(status == .offline ? 0.4 : 1))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 1)
                )
                .offset(x: 4, y: 4)
        }
        .frame(width: 44, height: 44)
    }

    private var isEmoji: Bool {
        guard let profileURL else { return false }
        // Check if it's a single emoji character (not a URL)
        return profileURL.count <= 2 && !profileURL.contains("http") && !profileURL.contains(".")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let profileURL, isEmoji {
            // Render emoji directly
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Text(profileURL)
                    .font(.title)
            }
        } else if let profileURL,
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

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct PresenceStatusBadge: View {
    let status: PresenceStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeBackground)
            .foregroundStyle(badgeForeground)
            .clipShape(Capsule())
    }

    private var badgeForeground: Color {
        status == .offline ? .secondary : status.indicatorColor
    }

    private var badgeBackground: Color {
        (status == .offline ? Color.secondary : status.indicatorColor).opacity(0.15)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.secondary)

            Text("No conversations yet")
                .font(.title2.weight(.semibold))

            Text("Start a new chat to see it appear here. Conversations will sync in real time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct SearchEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.secondary)

            Text("No matches found")
                .font(.title3.weight(.semibold))

            Text("Try another name or start a new chat using the compose button.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
