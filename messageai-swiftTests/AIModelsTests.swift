//
//  AIModelsTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 2025-10-23.
//

import XCTest
@testable import messageai_swift

final class AIModelsTests: XCTestCase {

    // MARK: - ThreadSummaryResponse Tests

    func testThreadSummaryResponseDecoding() throws {
        let json = """
        {
            "summary": "Team discussed Q4 roadmap and decided to prioritize feature X",
            "key_points": ["Roadmap review", "Feature X priority", "Budget approval"],
            "conversation_id": "conv-123",
            "timestamp": "2024-01-15T10:30:00Z",
            "message_count": 25
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(ThreadSummaryResponse.self, from: data)

        XCTAssertEqual(response.summary, "Team discussed Q4 roadmap and decided to prioritize feature X")
        XCTAssertEqual(response.keyPoints.count, 3)
        XCTAssertEqual(response.keyPoints[0], "Roadmap review")
        XCTAssertEqual(response.conversationId, "conv-123")
        XCTAssertEqual(response.messageCount, 25)
    }

    // MARK: - ActionItem Tests

    func testActionItemDecoding() throws {
        let json = """
        {
            "id": "action-1",
            "task": "Complete budget report",
            "assigned_to": "user-123",
            "due_date": "2024-01-20T17:00:00Z",
            "priority": "high",
            "status": "pending",
            "conversation_id": "conv-123",
            "created_at": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let actionItem = try decoder.decode(ActionItem.self, from: data)

        XCTAssertEqual(actionItem.id, "action-1")
        XCTAssertEqual(actionItem.task, "Complete budget report")
        XCTAssertEqual(actionItem.assignedTo, "user-123")
        XCTAssertNotNil(actionItem.dueDate)
        XCTAssertEqual(actionItem.priority, .high)
        XCTAssertEqual(actionItem.status, .pending)
        XCTAssertEqual(actionItem.conversationId, "conv-123")
    }

    func testActionItemPriorityEnum() throws {
        XCTAssertEqual(ActionItemPriority.low.rawValue, "low")
        XCTAssertEqual(ActionItemPriority.medium.rawValue, "medium")
        XCTAssertEqual(ActionItemPriority.high.rawValue, "high")
        XCTAssertEqual(ActionItemPriority.urgent.rawValue, "urgent")
    }

    func testActionItemStatusEnum() throws {
        XCTAssertEqual(ActionItemStatus.pending.rawValue, "pending")
        XCTAssertEqual(ActionItemStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(ActionItemStatus.completed.rawValue, "completed")
        XCTAssertEqual(ActionItemStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - SearchResult Tests

    func testSearchResultDecoding() throws {
        let json = """
        {
            "id": "search-1",
            "conversation_id": "conv-123",
            "message_id": "msg-456",
            "snippet": "Let's schedule a meeting to discuss the Q4 roadmap",
            "relevance_score": 0.87,
            "timestamp": "2024-01-15T10:30:00Z",
            "participant_names": ["Alice", "Bob"]
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(result.id, "search-1")
        XCTAssertEqual(result.conversationId, "conv-123")
        XCTAssertEqual(result.messageId, "msg-456")
        XCTAssertEqual(result.snippet, "Let's schedule a meeting to discuss the Q4 roadmap")
        XCTAssertEqual(result.relevanceScore, 0.87, accuracy: 0.001)
        XCTAssertEqual(result.participantNames.count, 2)
    }

    // MARK: - PriorityUpdate Tests

    func testPriorityUpdateDecoding() throws {
        let json = """
        {
            "message_id": "msg-123",
            "conversation_id": "conv-456",
            "priority": "urgent",
            "confidence": 0.92,
            "reasoning": "Contains time-sensitive keywords",
            "detected_at": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let update = try decoder.decode(PriorityUpdate.self, from: data)

        XCTAssertEqual(update.messageId, "msg-123")
        XCTAssertEqual(update.conversationId, "conv-456")
        XCTAssertEqual(update.priority, .urgent)
        XCTAssertEqual(update.confidence, 0.92, accuracy: 0.001)
        XCTAssertEqual(update.reasoning, "Contains time-sensitive keywords")
    }

    func testMessagePriorityEnum() throws {
        XCTAssertEqual(MessagePriority.low.rawValue, "low")
        XCTAssertEqual(MessagePriority.normal.rawValue, "normal")
        XCTAssertEqual(MessagePriority.high.rawValue, "high")
        XCTAssertEqual(MessagePriority.urgent.rawValue, "urgent")
    }

    // MARK: - Decision Tests

    func testDecisionDecoding() throws {
        let json = """
        {
            "id": "decision-1",
            "title": "Adopt React for frontend",
            "description": "Team agreed to use React framework",
            "conversation_id": "conv-123",
            "decided_by": ["user-1", "user-2"],
            "status": "approved",
            "related_action_items": ["action-1", "action-2"],
            "created_at": "2024-01-15T10:30:00Z",
            "deadline": "2024-02-01T17:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decision = try decoder.decode(Decision.self, from: data)

        XCTAssertEqual(decision.id, "decision-1")
        XCTAssertEqual(decision.title, "Adopt React for frontend")
        XCTAssertEqual(decision.status, .approved)
        XCTAssertEqual(decision.decidedBy.count, 2)
        XCTAssertEqual(decision.relatedActionItems.count, 2)
        XCTAssertNotNil(decision.deadline)
    }

    func testDecisionStatusEnum() throws {
        XCTAssertEqual(DecisionStatus.proposed.rawValue, "proposed")
        XCTAssertEqual(DecisionStatus.approved.rawValue, "approved")
        XCTAssertEqual(DecisionStatus.implemented.rawValue, "implemented")
        XCTAssertEqual(DecisionStatus.revisiting.rawValue, "revisiting")
        XCTAssertEqual(DecisionStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - MeetingTimeSuggestion Tests

    func testMeetingTimeSuggestionDecoding() throws {
        let json = """
        {
            "startTime": "2024-01-20T14:00:00Z",
            "endTime": "2024-01-20T15:00:00Z",
            "score": 0.95,
            "justification": "Good availability across team",
            "dayOfWeek": "Friday",
            "timeOfDay": "afternoon"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let suggestion = try decoder.decode(MeetingTimeSuggestion.self, from: data)

        XCTAssertNotNil(suggestion.id)
        XCTAssertEqual(suggestion.score, 0.95, accuracy: 0.001)
        XCTAssertEqual(suggestion.justification, "Good availability across team")
        XCTAssertEqual(suggestion.dayOfWeek, "Friday")
        XCTAssertEqual(suggestion.timeOfDay, .afternoon)
    }

    func testMeetingSuggestionsResponseDecoding() throws {
        let json = """
        {
            "suggestions": [
                {
                    "startTime": "2024-01-20T14:00:00Z",
                    "endTime": "2024-01-20T15:00:00Z",
                    "score": 0.95,
                    "justification": "Good availability",
                    "dayOfWeek": "Friday",
                    "timeOfDay": "afternoon"
                }
            ],
            "conversation_id": "conv-123",
            "duration_minutes": 60,
            "participant_count": 3,
            "generated_at": "2024-01-15T10:30:00Z",
            "expires_at": "2024-01-22T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(MeetingSuggestionsResponse.self, from: data)

        XCTAssertEqual(response.suggestions.count, 1)
        XCTAssertEqual(response.conversationId, "conv-123")
        XCTAssertEqual(response.durationMinutes, 60)
        XCTAssertEqual(response.participantCount, 3)
    }

    // MARK: - SchedulingIntent Tests

    func testSchedulingIntentDecoding() throws {
        let json = """
        {
            "message_id": "msg-123",
            "conversation_id": "conv-456",
            "detected_intent": "schedule_meeting",
            "confidence": 0.91,
            "suggested_action": "Show meeting time suggestions",
            "detected_at": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let intent = try decoder.decode(SchedulingIntent.self, from: data)

        XCTAssertEqual(intent.messageId, "msg-123")
        XCTAssertEqual(intent.detectedIntent, "schedule_meeting")
        XCTAssertEqual(intent.confidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(intent.suggestedAction, "Show meeting time suggestions")
    }

    // MARK: - ProactiveInsight Tests

    func testProactiveInsightDecoding() throws {
        let json = """
        {
            "id": "insight-1",
            "type": "unresolved_action_item",
            "title": "3 overdue action items",
            "description": "You have 3 action items past their due date",
            "actionable": true,
            "conversation_ids": ["conv-1", "conv-2"],
            "priority": "high",
            "generated_at": "2024-01-15T10:30:00Z",
            "expires_at": "2024-01-16T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let insight = try decoder.decode(ProactiveInsight.self, from: data)

        XCTAssertEqual(insight.id, "insight-1")
        XCTAssertEqual(insight.type, .unresolvedActionItem)
        XCTAssertEqual(insight.title, "3 overdue action items")
        XCTAssertTrue(insight.actionable)
        XCTAssertEqual(insight.conversationIds.count, 2)
        XCTAssertEqual(insight.priority, .high)
        XCTAssertNotNil(insight.expiresAt)
    }

    func testInsightTypeEnum() throws {
        XCTAssertEqual(InsightType.unresolvedActionItem.rawValue, "unresolved_action_item")
        XCTAssertEqual(InsightType.staleDecision.rawValue, "stale_decision")
        XCTAssertEqual(InsightType.upcomingDeadline.rawValue, "upcoming_deadline")
        XCTAssertEqual(InsightType.schedulingConflict.rawValue, "scheduling_conflict")
        XCTAssertEqual(InsightType.blockedProgress.rawValue, "blocked_progress")
    }

    // MARK: - AIResponse Generic Wrapper Tests

    func testAIResponseSuccessDecoding() throws {
        let json = """
        {
            "success": true,
            "data": {
                "summary": "Test summary",
                "key_points": ["Point 1"],
                "conversation_id": "conv-123",
                "timestamp": "2024-01-15T10:30:00Z",
                "message_count": 10
            },
            "error": null,
            "timestamp": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(AIResponse<ThreadSummaryResponse>.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.data?.summary, "Test summary")
    }

    func testAIResponseErrorDecoding() throws {
        let json = """
        {
            "success": false,
            "data": null,
            "error": "Failed to generate summary",
            "timestamp": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(AIResponse<ThreadSummaryResponse>.self, from: data)

        XCTAssertFalse(response.success)
        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "Failed to generate summary")
    }

    // MARK: - Edge Cases

    func testActionItemWithNullOptionalFields() throws {
        let json = """
        {
            "id": "action-1",
            "description": "Complete task",
            "assigned_to": null,
            "due_date": null,
            "priority": "medium",
            "status": "pending",
            "conversation_id": "conv-123",
            "created_at": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let actionItem = try decoder.decode(ActionItem.self, from: data)

        XCTAssertNil(actionItem.assignedTo)
        XCTAssertNil(actionItem.dueDate)
        XCTAssertEqual(actionItem.priority, .medium)
    }

    func testDecisionWithNullDeadline() throws {
        let json = """
        {
            "id": "decision-1",
            "title": "Test decision",
            "description": "Test",
            "conversation_id": "conv-123",
            "decided_by": ["user-1"],
            "status": "proposed",
            "related_action_items": [],
            "created_at": "2024-01-15T10:30:00Z",
            "deadline": null
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decision = try decoder.decode(Decision.self, from: data)

        XCTAssertNil(decision.deadline)
    }
}
