//
//  UsersDebugView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 11/19/25.
//

import Foundation
import SwiftData
import SwiftUI

struct UsersDebugView: View {
    let currentUser: AuthService.AppUser

    @Query private var users: [UserEntity]
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedUsers) { user in
                    UserRowView(
                        user: user,
                        isCurrentUser: user.id == currentUser.id,
                        isOnline: networkMonitor.isConnected
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Users")
        }
    }

    private var sortedUsers: [UserEntity] {
        users.sorted { lhs, rhs in
            let lhsRank = lhs.presenceStatus.sortRank
            let rhsRank = rhs.presenceStatus.sortRank
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.lastSeen > rhs.lastSeen
        }
    }
}

private struct UserRowView: View {
    let user: UserEntity
    let isCurrentUser: Bool
    let isOnline: Bool

    private var statusText: String {
        let status = user.presenceStatus
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let reference = formatter.localizedString(for: user.lastSeen, relativeTo: Date())

        switch status {
        case .online:
            return "Online now"
        case .away:
            return "\(status.displayLabel) (\(reference))"
        case .offline:
            return "\(status.displayLabel) (\(reference))"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                user: user,
                size: 44,
                showPresenceIndicator: true,
                isOnline: isOnline
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName)
                        .font(.headline)
                    if isCurrentUser {
                        Text("(you)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(user.lastSeen.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}
