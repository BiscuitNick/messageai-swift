//
//  MeetingSuggestionEntityTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-24.
//

import XCTest
@testable import messageai_swift

final class MeetingSuggestionEntityTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithAllParameters() throws {
        let id = "meeting-123"
        let conversationId = "conv-456"
        let suggestions = [
            MeetingTimeSuggestionData(
                startTime: Date(timeIntervalSince1970: 1730044800), // 2024-10-27 14:00:00 UTC
                endTime: Date(timeIntervalSince1970: 1730048400),   // 2024-10-27 15:00:00 UTC
                score: 0.9,
                justification: "Peak activity time based on historical patterns",
                dayOfWeek: "Friday",
                timeOfDay: "afternoon"
            ),
            MeetingTimeSuggestionData(
                startTime: Date(timeIntervalSince1970: 1730073600), // 2024-10-27 22:00:00 UTC
                endTime: Date(timeIntervalSince1970: 1730077200),   // 2024-10-27 23:00:00 UTC
                score: 0.8,
                justification: "Alternative time slot with good availability",
                dayOfWeek: "Friday",
                timeOfDay: "evening"
            )
        ]
        let durationMinutes = 60
        let participantCount = 3
        let generatedAt = Date()
        let expiresAt = Date().addingTimeInterval(86400) // 24 hours
        let createdAt = Date().addingTimeInterval(-60)
        let updatedAt = Date()

        let meetingSuggestion = MeetingSuggestionEntity(
            id: id,
            conversationId: conversationId,
            suggestions: suggestions,
            durationMinutes: durationMinutes,
            participantCount: participantCount,
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(meetingSuggestion.id, id)
        XCTAssertEqual(meetingSuggestion.conversationId, conversationId)
        XCTAssertEqual(meetingSuggestion.durationMinutes, durationMinutes)
        XCTAssertEqual(meetingSuggestion.participantCount, participantCount)
        XCTAssertEqual(meetingSuggestion.generatedAt.timeIntervalSince1970, generatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(meetingSuggestion.expiresAt.timeIntervalSince1970, expiresAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(meetingSuggestion.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(meetingSuggestion.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 0.001)

        // Test suggestions array
        XCTAssertEqual(meetingSuggestion.suggestions.count, 2)
        XCTAssertEqual(meetingSuggestion.suggestions[0].score, 0.9)
        XCTAssertEqual(meetingSuggestion.suggestions[0].dayOfWeek, "Friday")
        XCTAssertEqual(meetingSuggestion.suggestions[0].timeOfDay, "afternoon")
        XCTAssertEqual(meetingSuggestion.suggestions[1].score, 0.8)
        XCTAssertEqual(meetingSuggestion.suggestions[1].timeOfDay, "evening")
    }

    func testInitializationWithDefaultValues() throws {
        let beforeInit = Date()
        let conversationId = "conv-123"
        let suggestions = [
            MeetingTimeSuggestionData(
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                score: 0.75,
                justification: "Test suggestion",
                dayOfWeek: "Monday",
                timeOfDay: "morning"
            )
        ]
        let generatedAt = Date()
        let expiresAt = Date().addingTimeInterval(86400)

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: conversationId,
            suggestions: suggestions,
            durationMinutes: 30,
            participantCount: 2,
            generatedAt: generatedAt,
            expiresAt: expiresAt
        )
        let afterInit = Date()

        // Check that ID is auto-generated
        XCTAssertFalse(meetingSuggestion.id.isEmpty)

        // Check that dates are approximately now
        XCTAssertGreaterThanOrEqual(meetingSuggestion.createdAt, beforeInit)
        XCTAssertLessThanOrEqual(meetingSuggestion.createdAt, afterInit)
        XCTAssertGreaterThanOrEqual(meetingSuggestion.updatedAt, beforeInit)
        XCTAssertLessThanOrEqual(meetingSuggestion.updatedAt, afterInit)
    }

    // MARK: - Suggestions Encoding/Decoding Tests

    func testSuggestionsEncodingDecoding() throws {
        let suggestions = [
            MeetingTimeSuggestionData(
                startTime: Date(timeIntervalSince1970: 1730044800),
                endTime: Date(timeIntervalSince1970: 1730048400),
                score: 0.95,
                justification: "Best time for all participants",
                dayOfWeek: "Monday",
                timeOfDay: "afternoon"
            ),
            MeetingTimeSuggestionData(
                startTime: Date(timeIntervalSince1970: 1730131200),
                endTime: Date(timeIntervalSince1970: 1730134800),
                score: 0.85,
                justification: "Alternative with good availability",
                dayOfWeek: "Tuesday",
                timeOfDay: "morning"
            ),
            MeetingTimeSuggestionData(
                startTime: Date(timeIntervalSince1970: 1730217600),
                endTime: Date(timeIntervalSince1970: 1730221200),
                score: 0.70,
                justification: "Third option",
                dayOfWeek: "Wednesday",
                timeOfDay: "evening"
            )
        ]

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-789",
            suggestions: suggestions,
            durationMinutes: 60,
            participantCount: 4,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        let decodedSuggestions = meetingSuggestion.suggestions

        XCTAssertEqual(decodedSuggestions.count, 3)
        XCTAssertEqual(decodedSuggestions[0].score, 0.95)
        XCTAssertEqual(decodedSuggestions[0].dayOfWeek, "Monday")
        XCTAssertEqual(decodedSuggestions[0].timeOfDay, "afternoon")
        XCTAssertEqual(decodedSuggestions[1].score, 0.85)
        XCTAssertEqual(decodedSuggestions[1].dayOfWeek, "Tuesday")
        XCTAssertEqual(decodedSuggestions[1].timeOfDay, "morning")
        XCTAssertEqual(decodedSuggestions[2].score, 0.70)
        XCTAssertEqual(decodedSuggestions[2].dayOfWeek, "Wednesday")
        XCTAssertEqual(decodedSuggestions[2].timeOfDay, "evening")

        // Test timestamp accuracy
        XCTAssertEqual(decodedSuggestions[0].startTime.timeIntervalSince1970, 1730044800, accuracy: 1.0)
        XCTAssertEqual(decodedSuggestions[0].endTime.timeIntervalSince1970, 1730048400, accuracy: 1.0)
    }

    func testSuggestionsModification() throws {
        let initialSuggestions = [
            MeetingTimeSuggestionData(
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                score: 0.8,
                justification: "Initial suggestion",
                dayOfWeek: "Thursday",
                timeOfDay: "morning"
            )
        ]

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-modify",
            suggestions: initialSuggestions,
            durationMinutes: 45,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        XCTAssertEqual(meetingSuggestion.suggestions.count, 1)

        // Modify suggestions
        let newSuggestions = [
            MeetingTimeSuggestionData(
                startTime: Date().addingTimeInterval(86400),
                endTime: Date().addingTimeInterval(90000),
                score: 0.9,
                justification: "Updated suggestion",
                dayOfWeek: "Friday",
                timeOfDay: "afternoon"
            ),
            MeetingTimeSuggestionData(
                startTime: Date().addingTimeInterval(172800),
                endTime: Date().addingTimeInterval(176400),
                score: 0.85,
                justification: "Second updated suggestion",
                dayOfWeek: "Saturday",
                timeOfDay: "morning"
            )
        ]

        meetingSuggestion.suggestions = newSuggestions

        XCTAssertEqual(meetingSuggestion.suggestions.count, 2)
        XCTAssertEqual(meetingSuggestion.suggestions[0].score, 0.9)
        XCTAssertEqual(meetingSuggestion.suggestions[0].dayOfWeek, "Friday")
        XCTAssertEqual(meetingSuggestion.suggestions[1].score, 0.85)
        XCTAssertEqual(meetingSuggestion.suggestions[1].dayOfWeek, "Saturday")
    }

    func testEmptySuggestionsArray() throws {
        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-empty",
            suggestions: [],
            durationMinutes: 30,
            participantCount: 1,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        XCTAssertEqual(meetingSuggestion.suggestions.count, 0)
        XCTAssertFalse(meetingSuggestion.isValid) // Should be invalid with empty suggestions
    }

    // MARK: - Expiry Tests

    func testIsExpiredWhenNotExpired() throws {
        let futureExpiryDate = Date().addingTimeInterval(3600) // 1 hour in the future

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-valid",
            suggestions: [
                MeetingTimeSuggestionData(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    score: 0.8,
                    justification: "Test",
                    dayOfWeek: "Monday",
                    timeOfDay: "morning"
                )
            ],
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: futureExpiryDate
        )

        XCTAssertFalse(meetingSuggestion.isExpired)
        XCTAssertTrue(meetingSuggestion.isValid)
    }

    func testIsExpiredWhenExpired() throws {
        let pastExpiryDate = Date().addingTimeInterval(-3600) // 1 hour in the past

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-expired",
            suggestions: [
                MeetingTimeSuggestionData(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    score: 0.8,
                    justification: "Test",
                    dayOfWeek: "Monday",
                    timeOfDay: "morning"
                )
            ],
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date().addingTimeInterval(-7200),
            expiresAt: pastExpiryDate
        )

        XCTAssertTrue(meetingSuggestion.isExpired)
        XCTAssertFalse(meetingSuggestion.isValid)
    }

    func testIsValidWithExpiredButNonEmptySuggestions() throws {
        let pastExpiryDate = Date().addingTimeInterval(-3600)

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-test",
            suggestions: [
                MeetingTimeSuggestionData(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    score: 0.8,
                    justification: "Test",
                    dayOfWeek: "Monday",
                    timeOfDay: "morning"
                )
            ],
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: pastExpiryDate
        )

        // Should be invalid because it's expired
        XCTAssertFalse(meetingSuggestion.isValid)
    }

    func testIsValidWithValidAndNonEmptySuggestions() throws {
        let futureExpiryDate = Date().addingTimeInterval(86400)

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-test",
            suggestions: [
                MeetingTimeSuggestionData(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    score: 0.8,
                    justification: "Test",
                    dayOfWeek: "Monday",
                    timeOfDay: "morning"
                )
            ],
            durationMinutes: 60,
            participantCount: 2,
            generatedAt: Date(),
            expiresAt: futureExpiryDate
        )

        // Should be valid: not expired and has suggestions
        XCTAssertTrue(meetingSuggestion.isValid)
    }

    // MARK: - MeetingTimeSuggestionData Tests

    func testMeetingTimeSuggestionDataInitialization() throws {
        let startTime = Date(timeIntervalSince1970: 1730044800)
        let endTime = Date(timeIntervalSince1970: 1730048400)
        let score = 0.92
        let justification = "Optimal time for all participants"
        let dayOfWeek = "Friday"
        let timeOfDay = "afternoon"

        let suggestion = MeetingTimeSuggestionData(
            startTime: startTime,
            endTime: endTime,
            score: score,
            justification: justification,
            dayOfWeek: dayOfWeek,
            timeOfDay: timeOfDay
        )

        XCTAssertEqual(suggestion.startTime.timeIntervalSince1970, startTime.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(suggestion.endTime.timeIntervalSince1970, endTime.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(suggestion.score, score)
        XCTAssertEqual(suggestion.justification, justification)
        XCTAssertEqual(suggestion.dayOfWeek, dayOfWeek)
        XCTAssertEqual(suggestion.timeOfDay, timeOfDay)
    }

    func testMeetingTimeSuggestionDataIdentifiable() throws {
        let startTime = Date(timeIntervalSince1970: 1730044800)
        let endTime = Date(timeIntervalSince1970: 1730048400)

        let suggestion = MeetingTimeSuggestionData(
            startTime: startTime,
            endTime: endTime,
            score: 0.8,
            justification: "Test",
            dayOfWeek: "Monday",
            timeOfDay: "morning"
        )

        // Test that ID is generated from timestamps
        XCTAssertFalse(suggestion.id.isEmpty)
        XCTAssertTrue(suggestion.id.contains("2024"))
    }

    func testMultipleSuggestionsHaveUniqueIds() throws {
        let suggestion1 = MeetingTimeSuggestionData(
            startTime: Date(timeIntervalSince1970: 1730044800),
            endTime: Date(timeIntervalSince1970: 1730048400),
            score: 0.9,
            justification: "First",
            dayOfWeek: "Monday",
            timeOfDay: "morning"
        )

        let suggestion2 = MeetingTimeSuggestionData(
            startTime: Date(timeIntervalSince1970: 1730131200),
            endTime: Date(timeIntervalSince1970: 1730134800),
            score: 0.8,
            justification: "Second",
            dayOfWeek: "Tuesday",
            timeOfDay: "afternoon"
        )

        XCTAssertNotEqual(suggestion1.id, suggestion2.id)
    }

    // MARK: - Edge Cases

    func testVeryLongJustificationText() throws {
        let longJustification = String(repeating: "This is a very detailed explanation. ", count: 100)

        let suggestion = MeetingTimeSuggestionData(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            score: 0.75,
            justification: longJustification,
            dayOfWeek: "Wednesday",
            timeOfDay: "evening"
        )

        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-long",
            suggestions: [suggestion],
            durationMinutes: 90,
            participantCount: 5,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        XCTAssertEqual(meetingSuggestion.suggestions[0].justification, longJustification)
    }

    func testMultipleParticipantsAndLongDuration() throws {
        let meetingSuggestion = MeetingSuggestionEntity(
            conversationId: "conv-large",
            suggestions: [
                MeetingTimeSuggestionData(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(7200), // 2 hours
                    score: 0.6,
                    justification: "Long meeting slot",
                    dayOfWeek: "Thursday",
                    timeOfDay: "afternoon"
                )
            ],
            durationMinutes: 120,
            participantCount: 10,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        XCTAssertEqual(meetingSuggestion.durationMinutes, 120)
        XCTAssertEqual(meetingSuggestion.participantCount, 10)
    }
}
