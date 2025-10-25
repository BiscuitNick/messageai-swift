//
//  BotAgentService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFunctions

/// Service responsible for bot agent interactions via Firebase Functions
@MainActor
final class BotAgentService {

    // MARK: - Types

    struct AgentMessage {
        let role: String
        let content: String
    }

    // MARK: - Properties

    private let functions: Functions

    // MARK: - Initialization

    init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    // MARK: - Public API

    /// Chat with a bot agent
    /// - Parameters:
    ///   - messages: Array of messages to send to the agent
    ///   - conversationId: Conversation ID for context
    /// - Throws: Firebase Functions errors
    func chatWithAgent(messages: [AgentMessage], conversationId: String) async throws {
        // Convert messages to format expected by Firebase function
        let messagesData = messages.map { message in
            return [
                "role": message.role,
                "content": message.content
            ]
        }

        let data: [String: Any] = [
            "messages": messagesData,
            "conversationId": conversationId
        ]

        _ = try await functions.httpsCallable("chatWithAgent").call(data)
        // Bot response is written directly to Firestore by the function
        // The listener will pick it up automatically

        #if DEBUG
        print("[BotAgentService] Chat with agent completed for conversation: \(conversationId)")
        #endif
    }

    /// Ensure bots exist in Firestore by calling Firebase Function
    /// - Throws: Firebase Functions errors
    func ensureBotExists() async throws {
        debugLog("Creating bots via Firebase Function...")
        _ = try await functions.httpsCallable("createBots").call()
        debugLog("Bots created successfully")
    }

    /// Delete all bots from Firestore by calling Firebase Function
    /// - Throws: Firebase Functions errors
    func deleteBots() async throws {
        debugLog("Deleting bots via Firebase Function...")
        _ = try await functions.httpsCallable("deleteBots").call()
        debugLog("Bots deleted successfully")
    }

    // MARK: - Private Helpers

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[BotAgentService]", message)
        #endif
    }
}
