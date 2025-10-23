//
//  BotEntityTests.swift
//  messageai-swiftTests
//
//  Created by Codex on 10/23/25.
//

import XCTest
@testable import messageai_swift

final class BotEntityTests: XCTestCase {

    func testInitializationStoresProvidedValues() throws {
        let createdAt = Date(timeIntervalSince1970: 1234)
        let updatedAt = Date(timeIntervalSince1970: 5678)

        let bot = BotEntity(
            id: "dash-bot",
            name: "Dash Bot",
            description: "Helpful assistant",
            avatarURL: "https://example.com/dash.png",
            category: "general",
            capabilities: ["conversation", "drafting"],
            model: "gpt-4o",
            systemPrompt: "Be helpful",
            tools: ["getCurrentTime"],
            isActive: true,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(bot.id, "dash-bot")
        XCTAssertEqual(bot.name, "Dash Bot")
        XCTAssertEqual(bot.botDescription, "Helpful assistant")
        XCTAssertEqual(bot.avatarURL, "https://example.com/dash.png")
        XCTAssertEqual(bot.category, "general")
        XCTAssertEqual(bot.capabilities, ["conversation", "drafting"])
        XCTAssertEqual(bot.model, "gpt-4o")
        XCTAssertEqual(bot.systemPrompt, "Be helpful")
        XCTAssertEqual(bot.tools, ["getCurrentTime"])
        XCTAssertTrue(bot.isActive)
        XCTAssertEqual(bot.createdAt, createdAt)
        XCTAssertEqual(bot.updatedAt, updatedAt)
    }

    func testCapabilitiesRoundTripUpdatesBackingStore() throws {
        let bot = BotEntity(
            id: "dad-bot",
            name: "Dad Bot",
            description: "Tell jokes",
            avatarURL: "https://example.com/dad.png",
            capabilities: ["humor"],
            tools: []
        )

        XCTAssertEqual(bot.capabilities, ["humor"])
        bot.capabilities = ["humor", "advice"]
        XCTAssertEqual(bot.capabilities, ["humor", "advice"])
    }

    func testToolsRoundTripUpdatesBackingStore() throws {
        let bot = BotEntity(
            id: "dash-bot",
            name: "Dash Bot",
            description: "Helper",
            avatarURL: "https://example.com/dash.png",
            tools: ["draftMessage"]
        )

        XCTAssertEqual(bot.tools, ["draftMessage"])
        bot.tools = ["getCurrentTime", "draftMessage"]
        XCTAssertEqual(bot.tools, ["getCurrentTime", "draftMessage"])
    }

    func testDefaultValuesMatchModelExpectations() throws {
        let bot = BotEntity(
            id: "new-bot",
            name: "New Bot",
            description: "Fresh off the press",
            avatarURL: "https://example.com/new.png"
        )

        XCTAssertEqual(bot.category, "general")
        XCTAssertEqual(bot.capabilities, [])
        XCTAssertEqual(bot.model, "gemini-1.5-flash")
        XCTAssertEqual(bot.systemPrompt, "")
        XCTAssertEqual(bot.tools, [])
        XCTAssertTrue(bot.isActive)
        XCTAssertNotNil(bot.createdAt)
        XCTAssertNotNil(bot.updatedAt)
    }
}
