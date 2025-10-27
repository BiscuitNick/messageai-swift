//
//  ConversationManagementService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for conversation creation and management
@MainActor
final class ConversationManagementService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var currentUserId: String?

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(modelContext: ModelContext, currentUserId: String) {
        self.modelContext = modelContext
        self.currentUserId = currentUserId
    }

    // MARK: - Public API

    /// Create a new conversation or return existing one
    /// - Parameters:
    ///   - participants: Array of participant user IDs
    ///   - isGroup: Whether this is a group conversation
    ///   - groupName: Optional group name
    /// - Returns: Conversation ID
    /// - Throws: MessagingError
    func createConversation(
        with participants: [String],
        isGroup: Bool = false,
        groupName: String? = nil
    ) async throws -> String {
        guard let currentUserId = currentUserId else {
            throw MessagingError.notAuthenticated
        }
        guard let modelContext = modelContext else {
            throw MessagingError.dataUnavailable
        }

        let filteredParticipants = participants.filter { $0 != currentUserId }
        guard !filteredParticipants.isEmpty else {
            throw MessagingError.invalidParticipants
        }

        let participantSet = Set(filteredParticipants + [currentUserId])

        // For direct messages, check for existing conversation
        if !isGroup {
            // Check local first
            if let existingId = try findExistingLocalConversation(
                matching: participantSet,
                isGroup: false
            ) {
                return existingId
            }

            // Check remote
            if let (existingId, existingData) = try await findExistingRemoteConversation(
                matching: participantSet,
                currentUserId: currentUserId,
                isGroup: false
            ) {
                try cacheConversation(
                    id: existingId,
                    data: existingData,
                    participantSet: participantSet,
                    isGroup: false,
                    currentUserId: currentUserId
                )
                return existingId
            }
        }

        // Create new conversation
        let conversationRef = db.collection("conversations").document()
        let now = Date()

        var data: [String: Any] = [
            "participantIds": Array(participantSet),
            "isGroup": isGroup,
            "adminIds": [currentUserId],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "unreadCount": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) }),
            "lastInteractionByUser": Dictionary(uniqueKeysWithValues: participantSet.map { ($0, Timestamp(date: now)) })
        ]

        let trimmedGroupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedGroupName, !trimmedGroupName.isEmpty {
            data["groupName"] = trimmedGroupName
        }

        try await conversationRef.setData(data)

        let conversationId = conversationRef.documentID

        // Cache to local SwiftData
        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == conversationId
            }
        )
        descriptor.fetchLimit = 1

        if try modelContext.fetch(descriptor).first == nil {
            let conversationEntity = ConversationEntity(
                id: conversationId,
                participantIds: Array(participantSet),
                isGroup: isGroup,
                groupName: trimmedGroupName,
                groupPictureURL: nil,
                adminIds: [currentUserId],
                lastMessage: nil,
                lastMessageTimestamp: nil,
                lastSenderId: nil,
                unreadCount: Dictionary(uniqueKeysWithValues: participantSet.map { ($0, 0) }),
                lastInteractionByUser: Dictionary(uniqueKeysWithValues: participantSet.map { ($0, now) }),
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(conversationEntity)
            try modelContext.save()
        }

        #if DEBUG
        print("[ConversationManagementService] Created conversation: \(conversationId)")
        #endif

        return conversationId
    }

    /// Upsert a user to local SwiftData
    /// - Parameters:
    ///   - id: User ID
    ///   - email: User email
    ///   - displayName: User display name
    ///   - profilePictureURL: Optional profile picture URL
    ///   - isOnline: Online status
    ///   - lastSeen: Last seen timestamp
    ///   - createdAt: Account creation timestamp
    /// - Throws: SwiftData errors
    func upsertLocalUser(
        id: String,
        email: String,
        displayName: String,
        profilePictureURL: String?,
        isOnline: Bool,
        lastSeen: Date,
        createdAt: Date
    ) throws {
        guard let modelContext = modelContext else { return }

        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.email = email
            existing.displayName = displayName
            existing.profilePictureURL = profilePictureURL
            existing.isOnline = isOnline
            existing.lastSeen = lastSeen
        } else {
            let user = UserEntity(
                id: id,
                email: email,
                displayName: displayName,
                profilePictureURL: profilePictureURL,
                isOnline: isOnline,
                lastSeen: lastSeen,
                createdAt: createdAt
            )
            modelContext.insert(user)
        }

        try modelContext.save()
    }

    /// Upsert a conversation to local SwiftData
    /// - Parameters:
    ///   - id: Conversation ID
    ///   - participantIds: Array of participant user IDs
    ///   - isGroup: Whether this is a group conversation
    ///   - groupName: Optional group name
    ///   - groupPictureURL: Optional group picture URL
    ///   - adminIds: Array of admin user IDs
    ///   - lastMessage: Last message text
    ///   - lastMessageTimestamp: Last message timestamp
    ///   - lastSenderId: Last message sender ID
    ///   - unreadCount: Unread count per user
    ///   - lastInteractionByUser: Last interaction timestamp per user
    ///   - createdAt: Creation timestamp
    ///   - updatedAt: Update timestamp
    /// - Throws: SwiftData errors
    func upsertLocalConversation(
        id: String,
        participantIds: [String],
        isGroup: Bool,
        groupName: String?,
        groupPictureURL: String?,
        adminIds: [String],
        lastMessage: String?,
        lastMessageTimestamp: Date?,
        lastSenderId: String?,
        unreadCount: [String: Int],
        lastInteractionByUser: [String: Date],
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard let modelContext = modelContext else { return }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.id == id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.participantIds = participantIds
            existing.isGroup = isGroup
            existing.groupName = groupName
            existing.groupPictureURL = groupPictureURL
            existing.adminIds = adminIds
            existing.lastMessage = lastMessage
            existing.lastMessageTimestamp = lastMessageTimestamp
            existing.lastSenderId = lastSenderId
            existing.unreadCount = unreadCount
            if !lastInteractionByUser.isEmpty {
                existing.lastInteractionByUser = lastInteractionByUser
            }
            existing.createdAt = createdAt
            existing.updatedAt = updatedAt
        } else {
            let conversation = ConversationEntity(
                id: id,
                participantIds: participantIds,
                isGroup: isGroup,
                groupName: groupName,
                groupPictureURL: groupPictureURL,
                adminIds: adminIds,
                lastMessage: lastMessage,
                lastMessageTimestamp: lastMessageTimestamp,
                lastSenderId: lastSenderId,
                unreadCount: unreadCount,
                lastInteractionByUser: lastInteractionByUser,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            modelContext.insert(conversation)
        }

        try modelContext.save()
    }

    // MARK: - Private Helpers

    /// Find existing local conversation matching participant set
    private func findExistingLocalConversation(
        matching participantSet: Set<String>,
        isGroup: Bool
    ) throws -> String? {
        guard let modelContext = modelContext else { return nil }

        var descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate<ConversationEntity> { conversation in
                conversation.isGroup == isGroup
            }
        )

        let candidates = try modelContext.fetch(descriptor)
        return candidates.first { Set($0.participantIds) == participantSet }?.id
    }

    /// Find existing remote conversation matching participant set
    private func findExistingRemoteConversation(
        matching participantSet: Set<String>,
        currentUserId: String,
        isGroup: Bool
    ) async throws -> (String, [String: Any])? {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()

        for document in snapshot.documents {
            let data = document.data()
            let participants = SwiftDataHelper.stringArray(from: data["participantIds"])
            let participantComparisonSet = Set(participants)
            let documentIsGroup = data["isGroup"] as? Bool ?? false

            if participantComparisonSet == participantSet && documentIsGroup == isGroup {
                return (document.documentID, data)
            }
        }

        return nil
    }

    /// Cache remote conversation to local SwiftData
    private func cacheConversation(
        id: String,
        data: [String: Any],
        participantSet: Set<String>,
        isGroup: Bool,
        currentUserId: String
    ) throws {
        let participants = SwiftDataHelper.stringArray(from: data["participantIds"])
        let adminIds = SwiftDataHelper.stringArray(from: data["adminIds"])
        let resolvedParticipants = participants.isEmpty ? Array(participantSet) : participants
        let resolvedAdminIds = adminIds.isEmpty ? [currentUserId] : adminIds
        let groupName = data["groupName"] as? String
        let groupPictureURL = data["groupPictureURL"] as? String
        let lastMessage = data["lastMessage"] as? String
        let lastTimestamp = (data["lastMessageTimestamp"] as? Timestamp)?.dateValue()
        let lastSenderId = data["lastSenderId"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let unreadCount = SwiftDataHelper.parseUnreadCount(
            data["unreadCount"],
            participants: resolvedParticipants
        )
        let lastInteractionByUser = Self.parseTimestampDictionary(data["lastInteractionByUser"])

        try upsertLocalConversation(
            id: id,
            participantIds: resolvedParticipants,
            isGroup: isGroup,
            groupName: groupName,
            groupPictureURL: groupPictureURL,
            adminIds: resolvedAdminIds,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastTimestamp,
            lastSenderId: lastSenderId,
            unreadCount: unreadCount,
            lastInteractionByUser: lastInteractionByUser,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Parse timestamp dictionary from Firestore data
    private static func parseTimestampDictionary(_ value: Any?) -> [String: Date] {
        guard let map = value as? [String: Any] else { return [:] }
        var result: [String: Date] = [:]

        for (userId, raw) in map {
            if let timestamp = raw as? Timestamp {
                result[userId] = timestamp.dateValue()
            } else if let date = raw as? Date {
                result[userId] = date
            }
        }

        return result
    }
}
