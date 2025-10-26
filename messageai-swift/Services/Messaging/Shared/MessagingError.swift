//
//  MessagingError.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation

/// Errors that can occur in messaging operations
enum MessagingError: Error, LocalizedError {
    case notAuthenticated
    case invalidParticipants
    case dataUnavailable
    case invalidData(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to send messages."
        case .invalidParticipants:
            return "Select at least one other participant."
        case .dataUnavailable:
            return "Local data store not ready. Try again shortly."
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .timeout:
            return "Message send timed out. Check your connection."
        }
    }
}
