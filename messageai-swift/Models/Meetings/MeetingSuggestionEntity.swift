//
//  MeetingSuggestionEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

@Model
final class MeetingSuggestionEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var suggestionsData: Data
    var durationMinutes: Int
    var participantCount: Int
    var generatedAt: Date
    var expiresAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        suggestions: [MeetingTimeSuggestionData],
        durationMinutes: Int,
        participantCount: Int,
        generatedAt: Date,
        expiresAt: Date,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.suggestionsData = LocalJSONCoder.encode(suggestions)
        self.durationMinutes = durationMinutes
        self.participantCount = participantCount
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var suggestions: [MeetingTimeSuggestionData] {
        get { LocalJSONCoder.decode(suggestionsData, fallback: []) }
        set { suggestionsData = LocalJSONCoder.encode(newValue) }
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isValid: Bool {
        !isExpired && !suggestions.isEmpty
    }
}

@Model
final class SchedulingSuggestionSnoozeEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var snoozedUntil: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        snoozedUntil: Date,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isSnoozed: Bool {
        Date() < snoozedUntil
    }

    var isExpired: Bool {
        !isSnoozed
    }
}

struct MeetingTimeSuggestionData: Codable, Identifiable {
    var id: String { "\(startTime.ISO8601Format())-\(endTime.ISO8601Format())" }
    let startTime: Date
    let endTime: Date
    let score: Double
    let justification: String
    let dayOfWeek: String
    let timeOfDay: String

    init(
        startTime: Date,
        endTime: Date,
        score: Double,
        justification: String,
        dayOfWeek: String,
        timeOfDay: String
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.score = score
        self.justification = justification
        self.dayOfWeek = dayOfWeek
        self.timeOfDay = timeOfDay
    }
}
