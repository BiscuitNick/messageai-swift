//
//  TypingComponents.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct TypingIndicator: View {
    let bot: BotEntity?
    let isOnline: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let bot {
                AvatarView(
                    bot: bot,
                    size: 32,
                    showPresenceIndicator: true,
                    isOnline: isOnline
                )
            }

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationScale)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationScale
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(.leading, 8)
        .onAppear {
            animationScale = 1.2
        }
    }

    @State private var animationScale: CGFloat = 0.8
}

struct TypingBubble: View {
    let user: UserEntity?
    let displayName: String
    let isGroupChat: Bool
    let isOnline: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // User avatar (same style as bot typing indicator)
            if let user {
                AvatarView(
                    user: user,
                    size: 32,
                    showPresenceIndicator: true,
                    isOnline: isOnline
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                // Show name for group chats above the bubble
                if isGroupChat {
                    Text(displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationScale)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: animationScale
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Spacer()
        }
        .padding(.leading, 8)
        .onAppear {
            animationScale = 1.2
        }
        .accessibilityLabel(isGroupChat ? "\(displayName) is typing" : "User is typing")
    }

    @State private var animationScale: CGFloat = 0.8

    init(user: UserEntity?, displayName: String, isGroupChat: Bool, isOnline: Bool) {
        self.user = user
        self.displayName = displayName
        self.isGroupChat = isGroupChat
        self.isOnline = isOnline
    }
}
