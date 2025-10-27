//
//  PresenceService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import Foundation
import SwiftData

/// Service responsible for user presence management (online/offline status)
@MainActor
final class PresenceService {

    // MARK: - Properties

    private weak var modelContext: ModelContext?
    private weak var firestoreCoordinator: FirestoreCoordinator?

    private var lastActivityTimestamp: Date = Date()
    private var presenceHeartbeatTask: Task<Void, Never>?
    private var offlineTimerTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(
        modelContext: ModelContext,
        firestoreCoordinator: FirestoreCoordinator
    ) {
        if self.modelContext !== modelContext {
            self.modelContext = modelContext
        }
        self.firestoreCoordinator = firestoreCoordinator
    }

    // MARK: - Public API

    /// Mark user as online
    func markUserOnline(userId: String) async {
        let now = Date()
        lastActivityTimestamp = now
        await updatePresence(userId: userId, isOnline: true, lastSeenOverride: now)
    }

    /// Mark user as offline
    func markUserOffline(userId: String, lastSeenOverride: Date? = nil) async {
        let timestamp = lastSeenOverride ?? Date()
        lastActivityTimestamp = timestamp
        await updatePresence(userId: userId, isOnline: false, lastSeenOverride: timestamp)
    }

    /// Set user offline (also updates local descriptor)
    func setUserOffline(userId: String) async {
        guard let modelContext = modelContext else { return }

        let targetId = userId
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate<UserEntity> { user in
                user.id == targetId
            }
        )
        descriptor.fetchLimit = 1

        let now = Date()
        lastActivityTimestamp = now
        await updatePresence(userId: userId, isOnline: false, descriptor: descriptor, lastSeenOverride: now)
    }

    /// Start heartbeat to keep user online
    func startHeartbeat(userId: String) {
        guard presenceHeartbeatTask == nil else { return }
        presenceHeartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.markUserOnline(userId: userId)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Stop heartbeat
    func stopHeartbeat() {
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = nil
    }

    /// Handle scene becoming active
    func sceneDidBecomeActive(userId: String?) {
        cancelOfflineTimer()
        if let userId {
            startHeartbeat(userId: userId)
            Task { await self.markUserOnline(userId: userId) }
        }
    }

    /// Handle scene entering background
    func sceneDidEnterBackground(userId: String?) {
        stopHeartbeat()
        guard let userId else {
            cancelOfflineTimer()
            return
        }
        lastActivityTimestamp = Date()
        scheduleOfflineTimer(userId: userId)
    }

    /// Cancel all presence tasks
    func cancelPresenceTasks() {
        stopHeartbeat()
        cancelOfflineTimer()
    }

    // MARK: - Private Helpers

    private func updatePresence(
        userId: String,
        isOnline: Bool,
        descriptor: FetchDescriptor<UserEntity>? = nil,
        lastSeenOverride: Date? = nil
    ) async {
        guard let modelContext = modelContext else { return }

        let fetchDescriptor: FetchDescriptor<UserEntity>
        if let descriptor {
            fetchDescriptor = descriptor
        } else {
            var temp = FetchDescriptor<UserEntity>(
                predicate: #Predicate<UserEntity> { user in
                    user.id == userId
                }
            )
            temp.fetchLimit = 1
            fetchDescriptor = temp
        }

        let timestamp = lastSeenOverride ?? Date()

        do {
            if let existing = try modelContext.fetch(fetchDescriptor).first {
                existing.isOnline = isOnline
                existing.lastSeen = timestamp
                try modelContext.save()
            }
        } catch {
            debugLog("Failed to update local presence: \(error.localizedDescription)")
        }

        guard let service = firestoreCoordinator else { return }

        do {
            try await service.updatePresence(userId: userId, isOnline: isOnline, lastSeen: timestamp)
        } catch {
            debugLog("Failed to update Firestore presence: \(error.localizedDescription)")
        }
    }

    private func scheduleOfflineTimer(userId: String) {
        cancelOfflineTimer()
        let reference = lastActivityTimestamp
        offlineTimerTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            await self.markUserOffline(userId: userId, lastSeenOverride: reference)
        }
    }

    private func cancelOfflineTimer() {
        offlineTimerTask?.cancel()
        offlineTimerTask = nil
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[PresenceService]", message)
        #endif
    }
}
