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
}
