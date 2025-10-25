//
//  DecisionEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class DecisionEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var decisionText: String
    var contextSummary: String
    var participantIdsData: Data
    var decidedAt: Date
    var followUpStatusRawValue: String
    var confidenceScore: Double
    var reminderDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        decisionText: String,
        contextSummary: String,
        participantIds: [String],
        decidedAt: Date,
        followUpStatus: DecisionFollowUpStatus = .pending,
        confidenceScore: Double,
        reminderDate: Date? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.decisionText = decisionText
        self.contextSummary = contextSummary
        self.participantIdsData = LocalJSONCoder.encode(participantIds)
        self.decidedAt = decidedAt
        self.followUpStatusRawValue = followUpStatus.rawValue
        self.confidenceScore = confidenceScore
        self.reminderDate = reminderDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var participantIds: [String] {
        get {
            if let ids = try? LocalJSONCoder.decoder.decode([String].self, from: participantIdsData) {
                return ids
            }
            return []
        }
        set {
            participantIdsData = LocalJSONCoder.encode(newValue)
        }
    }

    var followUpStatus: DecisionFollowUpStatus {
        get { DecisionFollowUpStatus(rawValue: followUpStatusRawValue) ?? .pending }
        set { followUpStatusRawValue = newValue.rawValue }
    }
}

enum DecisionFollowUpStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case cancelled

    var displayLabel: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}
