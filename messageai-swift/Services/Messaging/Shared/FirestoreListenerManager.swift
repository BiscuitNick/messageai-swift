//
//  FirestoreListenerManager.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFirestore

/// Generic manager for Firestore listeners with lifecycle tracking
@MainActor
final class FirestoreListenerManager {

    // MARK: - Properties

    private var listeners: [String: ListenerRegistration] = [:]
    private var startTimes: [String: Date] = [:]

    // MARK: - Public API

    /// Register a listener with a unique identifier
    /// - Parameters:
    ///   - id: Unique identifier for this listener
    ///   - listener: The Firestore listener registration
    func register(id: String, listener: ListenerRegistration) {
        // Remove existing listener if present
        remove(id: id)

        // Register new listener
        listeners[id] = listener
        startTimes[id] = Date()

        #if DEBUG
        print("[FirestoreListenerManager] Registered listener: \(id)")
        #endif
    }

    /// Remove a specific listener
    /// - Parameter id: The listener identifier
    func remove(id: String) {
        if let listener = listeners[id] {
            listener.remove()
            listeners.removeValue(forKey: id)
            startTimes.removeValue(forKey: id)

            #if DEBUG
            print("[FirestoreListenerManager] Removed listener: \(id)")
            #endif
        }
    }

    /// Check if a listener is active
    /// - Parameter id: The listener identifier
    /// - Returns: True if listener exists, false otherwise
    func isActive(id: String) -> Bool {
        listeners[id] != nil
    }

    /// Get the start time for a listener
    /// - Parameter id: The listener identifier
    /// - Returns: The start time if listener exists
    func startTime(for id: String) -> Date? {
        startTimes[id]
    }

    /// Get count of active listeners
    var activeCount: Int {
        listeners.count
    }

    /// Get all active listener IDs
    var activeListenerIds: [String] {
        Array(listeners.keys)
    }

    /// Remove all listeners
    func removeAll() {
        let count = listeners.count
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        startTimes.removeAll()

        #if DEBUG
        print("[FirestoreListenerManager] Removed all listeners (\(count) total)")
        #endif
    }
}
