//
//  PriorityLevel.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation

enum PriorityLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case urgent
    case critical

    var displayLabel: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "⚪️"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .urgent: return "🔴"
        case .critical: return "🔥"
        }
    }

    var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        case .critical: return 4
        }
    }
}
