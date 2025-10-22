//
//  ConversationsRootView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData

struct ConversationsRootView: View {
    let currentUser: AuthService.AppUser

    @Environment(AuthService.self) private var authService
    @Environment(MessagingService.self) private var messagingService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\ConversationEntity.updatedAt, order: .reverse)])
    private var conversations: [ConversationEntity]

    @Query private var users: [UserEntity]

    private var userLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                } else {
                    List(conversations) { conversation in
                        NavigationLink {
                            ChatPlaceholderView(conversation: conversation)
                        } label: {
                            ConversationRow(
                                conversation: conversation,
                                currentUser: currentUser,
                                userLookup: userLookup
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Hi, \(currentUser.displayName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            authService.signOut()
                            messagingService.reset()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: ConversationEntity
    let currentUser: AuthService.AppUser
    let userLookup: [String: UserEntity]

    private var title: String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }

        let otherParticipant = conversation.participantIds
            .first(where: { $0 != currentUser.id })

        if let otherParticipant,
           let user = userLookup[otherParticipant] {
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

    var body: some View {
        HStack(spacing: 12) {
            AvatarPlaceholderView(initials: initials(for: title))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
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
}

private struct AvatarPlaceholderView: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 44, height: 44)
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

private struct ChatPlaceholderView: View {
    let conversation: ConversationEntity

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "ellipsis.bubble")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(.secondary)

            Text("Chat UI under construction")
                .font(.title3.weight(.semibold))

            Text("Messages will appear here once the chat screen is built.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(conversation.groupName ?? "Conversation")
    }
}
