//
//  PresenceStatus.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation

enum PresenceStatus: String, Codable, CaseIterable, Sendable {
    case online
    case away
    case offline

    static func status(isOnline: Bool, lastSeen: Date, reference: Date = Date()) -> PresenceStatus {
        guard isOnline else { return .offline }
        let interval = max(reference.timeIntervalSince(lastSeen), 0)
        if interval <= 120 {
            return .online
        } else if interval <= 600 {
            return .away
        } else {
            return .offline
        }
    }
}
