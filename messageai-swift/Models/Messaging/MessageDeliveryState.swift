//
//  MessageDeliveryState.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//  Updated to PRD-specified schema on 10/24/25.
//

import Foundation

enum MessageDeliveryState: String, Codable, CaseIterable, Sendable {
    case pending
    case sent
    case delivered
    case read
    case failed

    /// Migrate from legacy DeliveryStatus values
    init(fromLegacy status: String) {
        switch status {
        case "sending":
            self = .pending
        case "sent":
            self = .sent
        case "delivered":
            self = .delivered
        case "read":
            self = .read
        default:
            self = .sent // default fallback
        }
    }
}

/// Legacy enum for backward compatibility during migration
@available(*, deprecated, message: "Use MessageDeliveryState instead")
enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    case sending
    case sent
    case delivered
    case read

    var toDeliveryState: MessageDeliveryState {
        switch self {
        case .sending: return .pending
        case .sent: return .sent
        case .delivered: return .delivered
        case .read: return .read
        }
    }
}
