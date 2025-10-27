//
//  SwiftDataHelper.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFirestore

/// Helper utilities for SwiftData operations
struct SwiftDataHelper {

    // MARK: - Parsing Helpers

    /// Parse string array from Firestore value
    /// - Parameter value: The Firestore value (can be array, single string, or nil)
    /// - Returns: Array of strings
    static func stringArray(from value: Any?) -> [String] {
        if let arr = value as? [String] {
            return arr
        } else if let str = value as? String {
            return [str]
        }
        return []
    }

    /// Parse unread count dictionary from Firestore value
    /// - Parameters:
    ///   - value: The Firestore value
    ///   - participants: List of participant IDs
    /// - Returns: Dictionary mapping participant ID to unread count
    static func parseUnreadCount(_ value: Any?, participants: [String]) -> [String: Int] {
        if let dict = value as? [String: Int] {
            return dict
        }
        return [:]
    }

    /// Parse timestamp from Firestore value
    /// - Parameter value: The Firestore timestamp value
    /// - Returns: Date or current date as fallback
    static func parseTimestamp(_ value: Any?) -> Date {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        return Date()
    }

    /// Parse optional string from Firestore value
    /// - Parameter value: The Firestore value
    /// - Returns: String or nil
    static func parseOptionalString(_ value: Any?) -> String? {
        value as? String
    }

    /// Parse optional int from Firestore value
    /// - Parameter value: The Firestore value
    /// - Returns: Int or nil
    static func parseOptionalInt(_ value: Any?) -> Int? {
        value as? Int
    }

    /// Parse optional bool from Firestore value
    /// - Parameter value: The Firestore value
    /// - Returns: Bool or nil
    static func parseOptionalBool(_ value: Any?) -> Bool? {
        value as? Bool
    }

    /// Parse required string from Firestore value
    /// - Parameters:
    ///   - value: The Firestore value
    ///   - field: Field name for error messages
    /// - Returns: String
    /// - Throws: MessagingError if value is missing
    static func parseRequiredString(_ value: Any?, field: String) throws -> String {
        guard let string = value as? String else {
            throw MessagingError.invalidData("Missing required field: \(field)")
        }
        return string
    }

    /// Parse required timestamp from Firestore value
    /// - Parameters:
    ///   - value: The Firestore value
    ///   - field: Field name for error messages
    /// - Returns: Date
    /// - Throws: MessagingError if value is missing
    static func parseRequiredTimestamp(_ value: Any?, field: String) throws -> Date {
        guard let timestamp = value as? Timestamp else {
            throw MessagingError.invalidData("Missing required timestamp field: \(field)")
        }
        return timestamp.dateValue()
    }
}
