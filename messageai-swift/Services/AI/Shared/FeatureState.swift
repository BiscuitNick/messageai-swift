//
//  FeatureState.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation

/// Generic state container for AI features
/// Consolidates loading states, errors, and data for a specific conversation
@MainActor
@Observable
final class FeatureState<T> {

    // MARK: - Properties

    /// Per-conversation loading states
    var loadingStates: [String: Bool] = [:]

    /// Per-conversation error messages
    var errors: [String: String] = [:]

    /// Per-conversation cached data
    var data: [String: T] = [:]

    // MARK: - Convenience Accessors

    /// Check if a specific conversation is loading
    /// - Parameter conversationId: The conversation ID
    /// - Returns: True if loading, false otherwise
    func isLoading(_ conversationId: String) -> Bool {
        loadingStates[conversationId] ?? false
    }

    /// Get error for a specific conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Error message if one exists, nil otherwise
    func error(for conversationId: String) -> String? {
        errors[conversationId]
    }

    /// Get data for a specific conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Cached data if it exists, nil otherwise
    func get(_ conversationId: String) -> T? {
        data[conversationId]
    }

    // MARK: - State Management

    /// Set loading state for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - isLoading: Loading state
    func setLoading(_ conversationId: String, _ isLoading: Bool) {
        loadingStates[conversationId] = isLoading
    }

    /// Set error for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - error: Error message (nil to clear)
    func setError(_ conversationId: String, _ error: String?) {
        errors[conversationId] = error
    }

    /// Set data for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - value: The data value
    func set(_ conversationId: String, _ value: T) {
        data[conversationId] = value
    }

    /// Clear all state for a specific conversation
    /// - Parameter conversationId: The conversation ID
    func clear(_ conversationId: String) {
        loadingStates.removeValue(forKey: conversationId)
        errors.removeValue(forKey: conversationId)
        data.removeValue(forKey: conversationId)
    }

    /// Clear all state
    func clearAll() {
        loadingStates.removeAll()
        errors.removeAll()
        data.removeAll()
    }
}
