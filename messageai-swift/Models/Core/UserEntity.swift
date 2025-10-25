//
//  UserEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

@Model
final class UserEntity {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var email: String
    var displayName: String
    var profilePictureURL: String?
    var isOnline: Bool
    var lastSeen: Date
    var createdAt: Date

    init(
        id: String,
        email: String,
        displayName: String,
        profilePictureURL: String? = nil,
        isOnline: Bool = false,
        lastSeen: Date = .init(),
        createdAt: Date = .init()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.createdAt = createdAt
    }
}

extension UserEntity {
    var presenceStatus: PresenceStatus {
        PresenceStatus.status(isOnline: isOnline, lastSeen: lastSeen)
    }
}
