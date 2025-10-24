//
//  AIModelsTests.swift
//  messageai-swiftTests
//
//  Created by Claude Code on 10/23/25.
//

import XCTest
@testable import messageai_swift

final class AIModelsTests: XCTestCase {

    // MARK: - MessagePriority Tests

    func testMessagePriorityAllCases() throws {
        let allCases: [MessagePriority] = [.low, .medium, .high, .urgent]
        XCTAssertEqual(MessagePriority.allCases, allCases)
    }

    func testMessagePriorityRawValues() throws {
        XCTAssertEqual(MessagePriority.low.rawValue, "low")
        XCTAssertEqual(MessagePriority.medium.rawValue, "medium")
        XCTAssertEqual(MessagePriority.high.rawValue, "high")
        XCTAssertEqual(MessagePriority.urgent.rawValue, "urgent")
    }

    // MARK: - SummaryResponse Tests

    func testSummaryResponseDecoding() throws {
        let json = """
        {
            "summary": "This is a test summary",
            "conversationId": "conv-123",
            "generatedAt": 1698000000
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(SummaryResponse.self, from: data)

        XCTAssertEqual(response.summary, "This is a test summary")
        XCTAssertEqual(response.conversationId, "conv-123")
        XCTAssertNotNil(response.generatedAt)
    }

    func testSummaryResponseDecodingWithoutTimestamp() throws {
        let json = """
        {
            "summary": "Test summary",
            "conversationId": "conv-456"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let response = try decoder.decode(SummaryResponse.self, from: data)

        XCTAssertEqual(response.summary, "Test summary")
        XCTAssertEqual(response.conversationId, "conv-456")
        XCTAssertNil(response.generatedAt)
    }

    // MARK: - ActionItem Tests

    func testActionItemDecoding() throws {
        let json = """
        {
            "id": "action-1",
            "text": "Complete the report",
            "assignee": "user-123",
            "dueDate": 1698000000,
            "priority": "high",
            "isCompleted": false
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let item = try decoder.decode(ActionItem.self, from: data)

        XCTAssertEqual(item.id, "action-1")
        XCTAssertEqual(item.text, "Complete the report")
        XCTAssertEqual(item.assignee, "user-123")
        XCTAssertNotNil(item.dueDate)
        XCTAssertEqual(item.priority, .high)
        XCTAssertFalse(item.isCompleted)
    }

    func testActionItemDecodingWithDefaults() throws {
        let json = """
        {
            "id": "action-2",
            "text": "Simple task"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let item = try decoder.decode(ActionItem.self, from: data)

        XCTAssertEqual(item.id, "action-2")
        XCTAssertEqual(item.text, "Simple task")
        XCTAssertNil(item.assignee)
        XCTAssertNil(item.dueDate)
        XCTAssertEqual(item.priority, .medium)
        XCTAssertFalse(item.isCompleted)
    }

    func testActionItemsResponseDecoding() throws {
        let json = """
        {
            "actionItems": [
                {
                    "id": "action-1",
                    "text": "First task",
                    "priority": "low",
                    "isCompleted": true
                },
                {
                    "id": "action-2",
                    "text": "Second task",
                    "priority": "urgent",
                    "isCompleted": false
                }
            ],
            "conversationId": "conv-789"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let response = try decoder.decode(ActionItemsResponse.self, from: data)

        XCTAssertEqual(response.conversationId, "conv-789")
        XCTAssertEqual(response.actionItems.count, 2)
        XCTAssertEqual(response.actionItems[0].id, "action-1")
        XCTAssertEqual(response.actionItems[1].id, "action-2")
    }

    // MARK: - SearchResult Tests

    func testSearchResultDecoding() throws {
        let json = """
        {
            "id": "search-1",
            "messageId": "msg-123",
            "conversationId": "conv-456",
            "text": "Original message text",
            "snippet": "...message...",
            "relevanceScore": 0.95,
            "timestamp": 1698000000
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let result = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(result.id, "search-1")
        XCTAssertEqual(result.messageId, "msg-123")
        XCTAssertEqual(result.conversationId, "conv-456")
        XCTAssertEqual(result.text, "Original message text")
        XCTAssertEqual(result.snippet, "...message...")
        XCTAssertEqual(result.relevanceScore, 0.95, accuracy: 0.001)
        XCTAssertNotNil(result.timestamp)
    }

    func testSearchResultDecodingWithDefaults() throws {
        let json = """
        {
            "id": "search-2",
            "messageId": "msg-789",
            "conversationId": "conv-012",
            "text": "Message",
            "snippet": "Snippet"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let result = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(result.relevanceScore, 0.0)
        XCTAssertNil(result.timestamp)
    }

    func testSearchResponseDecoding() throws {
        let json = """
        {
            "results": [
                {
                    "id": "search-1",
                    "messageId": "msg-1",
                    "conversationId": "conv-1",
                    "text": "Text 1",
                    "snippet": "Snippet 1",
                    "relevanceScore": 0.9
                }
            ],
            "query": "test query"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let response = try decoder.decode(SearchResponse.self, from: data)

        XCTAssertEqual(response.query, "test query")
        XCTAssertEqual(response.results.count, 1)
    }

    // MARK: - Decision Tests

    func testDecisionDecoding() throws {
        let json = """
        {
            "id": "decision-1",
            "title": "Choose technology stack",
            "description": "We need to decide on the tech stack",
            "options": [
                {
                    "id": "opt-1",
                    "text": "Option A",
                    "pros": ["Fast", "Reliable"],
                    "cons": ["Expensive"]
                }
            ],
            "recommendation": "Option A",
            "confidence": 0.85
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let decision = try decoder.decode(Decision.self, from: data)

        XCTAssertEqual(decision.id, "decision-1")
        XCTAssertEqual(decision.title, "Choose technology stack")
        XCTAssertEqual(decision.options.count, 1)
        XCTAssertEqual(decision.recommendation, "Option A")
        XCTAssertEqual(decision.confidence, 0.85, accuracy: 0.001)
    }

    func testDecisionDecodingWithDefaults() throws {
        let json = """
        {
            "id": "decision-2",
            "title": "Simple decision",
            "description": "Description",
            "options": []
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let decision = try decoder.decode(Decision.self, from: data)

        XCTAssertNil(decision.recommendation)
        XCTAssertEqual(decision.confidence, 0.0)
    }

    // MARK: - Insight Tests

    func testInsightDecoding() throws {
        let json = """
        {
            "id": "insight-1",
            "type": "trend",
            "title": "Increased activity",
            "description": "User activity has increased by 50%",
            "actionable": true,
            "conversationId": "conv-123",
            "generatedAt": 1698000000
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let insight = try decoder.decode(Insight.self, from: data)

        XCTAssertEqual(insight.id, "insight-1")
        XCTAssertEqual(insight.type, .trend)
        XCTAssertEqual(insight.title, "Increased activity")
        XCTAssertTrue(insight.actionable)
        XCTAssertEqual(insight.conversationId, "conv-123")
        XCTAssertNotNil(insight.generatedAt)
    }

    func testInsightDecodingWithDefaults() throws {
        let json = """
        {
            "id": "insight-2",
            "title": "Basic insight",
            "description": "Description"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let insight = try decoder.decode(Insight.self, from: data)

        XCTAssertEqual(insight.type, .general)
        XCTAssertFalse(insight.actionable)
        XCTAssertNil(insight.conversationId)
        XCTAssertNil(insight.generatedAt)
    }

    func testInsightTypeAllCases() throws {
        let allTypes: [InsightType] = [.general, .trend, .recommendation, .warning, .opportunity]
        XCTAssertEqual(Set(allTypes), Set([InsightType.general, .trend, .recommendation, .warning, .opportunity]))
    }

    func testInsightsResponseDecoding() throws {
        let json = """
        {
            "insights": [
                {
                    "id": "insight-1",
                    "type": "recommendation",
                    "title": "Recommendation",
                    "description": "Description"
                }
            ],
            "userId": "user-123"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let response = try decoder.decode(InsightsResponse.self, from: data)

        XCTAssertEqual(response.userId, "user-123")
        XCTAssertEqual(response.insights.count, 1)
    }

    // MARK: - PriorityUpdateResponse Tests

    func testPriorityUpdateResponseDecoding() throws {
        let json = """
        {
            "success": true,
            "messageId": "msg-123",
            "priority": "urgent"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let response = try decoder.decode(PriorityUpdateResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.messageId, "msg-123")
        XCTAssertEqual(response.priority, .urgent)
    }
}
