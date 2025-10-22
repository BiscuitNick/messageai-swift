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

    @Environment(AuthService.self) private var authService
    @Environment(MessagingService.self) private var messagingService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\ConversationEntity.updatedAt, order: .reverse)])
    private var conversations: [ConversationEntity]

    @Query private var users: [UserEntity]

    @State private var isComposePresented = false
    @State private var isProfilePresented = false
    @State private var selectedConversationID: String?
    @State private var isSeedingMockData = false
    @State private var isOpeningBotChat = false
    @State private var alertData: AlertData?
    @State private var searchText: String = ""

    private var userLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }

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
                                    userLookup: userLookup
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isProfilePresented = true
                    } label: {
                        HStack(spacing: 8) {
                            ProfileThumbnailView(
                                photoURL: currentUser.photoURL,
                                initials: initials(for: currentUser.displayName)
                            )
                            VStack(alignment: .leading, spacing: 0) {
                                Text(currentUser.displayName)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityLabel("Open profile")
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
        .sheet(isPresented: $isProfilePresented) {
            ProfileView(
                user: currentUser,
                onSignOut: {
                    authService.signOut()
                    messagingService.reset()
                    selectedConversationID = nil
                },
                onStartBotChat: startBotChat,
                onAddMockData: addMockData,
                isBotBusy: isOpeningBotChat,
                isMockBusy: isSeedingMockData
            )
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
        .alert(
            alertData?.title ?? "",
            isPresented: .init(
                get: { alertData != nil },
                set: { if !$0 { alertData = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    alertData = nil
                }
            },
            message: {
                Text(alertData?.message ?? "")
            }
        )
        .overlay(alignment: .bottom) {
            ComposeButton(action: {
                isComposePresented = true
            }, isDisabled: selectableUsers.isEmpty)
            .padding(.bottom, 24)
        }
    }

    private func addMockData() {
        guard !isSeedingMockData else { return }
        isSeedingMockData = true
        Task { @MainActor in
            defer { isSeedingMockData = false }
            do {
                try await messagingService.seedMockData()
                alertData = AlertData(title: "Mock Data Ready", message: "Added sample teammates and a demo conversation.")
            } catch {
                alertData = AlertData(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func startBotChat() {
        guard !isOpeningBotChat else { return }
        isOpeningBotChat = true
        Task { @MainActor in
            defer { isOpeningBotChat = false }
            do {
                let conversationId = try await messagingService.ensureBotConversation()
                selectedConversationID = conversationId
                alertData = AlertData(title: "Support Chat Ready", message: "Say hello to MessageAI Bot!")
            } catch {
                alertData = AlertData(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func conversationTitle(for conversation: ConversationEntity) -> String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }
        let otherParticipant = conversation.participantIds.first { $0 != currentUser.id }
        if let otherParticipant,
           let user = userLookup[otherParticipant] {
            return user.displayName
        }
        return "Conversation"
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined().uppercased()
    }

    private struct AlertData {
        let title: String
        let message: String
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
            AvatarPlaceholderView(initials: initials(for: title), status: presenceStatus)

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
}

private struct ProfileThumbnailView: View {
    let photoURL: URL?
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))

            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Text(placeholderInitials)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(Circle())
            } else {
                Text(placeholderInitials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var placeholderInitials: String {
        initials.isEmpty ? "?" : initials
    }
}

private struct ComposeButton: View {
    let action: () -> Void
    let isDisabled: Bool

    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            Label("New Message", systemImage: "square.and.pencil")
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .circular)
                        .fill(isDisabled ? Color.gray.opacity(0.2) : Color.accentColor)
                )
                .foregroundStyle(isDisabled ? Color.gray : Color.white)
                .shadow(color: Color.black.opacity(isDisabled ? 0 : 0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct AvatarPlaceholderView: View {
    let initials: String
    let status: PresenceStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)

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
