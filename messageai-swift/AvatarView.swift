//
//  AvatarView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/23/25.
//

import SwiftUI

/// Shared avatar component used across the app for displaying user and bot avatars
/// with presence indicators and bot-specific styling
struct AvatarView: View {
    enum Entity {
        case user(UserEntity)
        case bot(BotEntity)
        case custom(initials: String, profileURL: String?)
    }

    let entity: Entity
    let size: CGFloat
    let showPresenceIndicator: Bool
    let isOnline: Bool

    init(
        entity: Entity,
        size: CGFloat = 44,
        showPresenceIndicator: Bool = true,
        isOnline: Bool = true
    ) {
        self.entity = entity
        self.size = size
        self.showPresenceIndicator = showPresenceIndicator
        self.isOnline = isOnline
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent

            if showPresenceIndicator {
                // Standard presence indicator for both users and bots
                Circle()
                    .fill(presenceColor.opacity(presenceStatus == .offline ? 0.4 : 1))
                    .frame(width: indicatorSize, height: indicatorSize)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
    }

    private var avatarContent: some View {
        Group {
            if let profileURL = profileURL, isEmoji(profileURL) {
                // Render emoji directly
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                    Text(profileURL)
                        .font(.system(size: size * 0.5))
                }
            } else if let profileURL = profileURL,
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
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
    }

    // MARK: - Computed Properties

    private var isBot: Bool {
        if case .bot = entity {
            return true
        }
        return false
    }

    private var initials: String {
        switch entity {
        case .user(let user):
            return makeInitials(from: user.displayName)
        case .bot(let bot):
            return makeInitials(from: bot.name)
        case .custom(let initials, _):
            return initials
        }
    }

    private var profileURL: String? {
        switch entity {
        case .user(let user):
            return user.profilePictureURL
        case .bot(let bot):
            return bot.avatarURL
        case .custom(_, let url):
            return url
        }
    }

    private var presenceStatus: PresenceStatus {
        switch entity {
        case .user(let user):
            return user.presenceStatus
        case .bot:
            return isOnline ? .online : .offline
        case .custom:
            return isOnline ? .online : .offline
        }
    }

    private var presenceColor: Color {
        presenceStatus.indicatorColor
    }

    private var backgroundColor: Color {
        isBot ? Color.purple.opacity(0.15) : Color.accentColor.opacity(0.15)
    }

    private var foregroundColor: Color {
        isBot ? Color.purple : Color.accentColor
    }

    private var indicatorSize: CGFloat {
        size * 0.25
    }

    // MARK: - Helper Methods

    private func isEmoji(_ string: String) -> Bool {
        // Check if it's a single emoji character (not a URL)
        return string.count <= 2 && !string.contains("http") && !string.contains(".")
    }

    private func makeInitials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.prefix(2).joined()
    }
}

// MARK: - Convenience Initializers

extension AvatarView {
    init(user: UserEntity, size: CGFloat = 44, showPresenceIndicator: Bool = true, isOnline: Bool = true) {
        self.init(
            entity: .user(user),
            size: size,
            showPresenceIndicator: showPresenceIndicator,
            isOnline: isOnline
        )
    }

    init(bot: BotEntity, size: CGFloat = 44, showPresenceIndicator: Bool = true, isOnline: Bool = true) {
        self.init(
            entity: .bot(bot),
            size: size,
            showPresenceIndicator: showPresenceIndicator,
            isOnline: isOnline
        )
    }
}
