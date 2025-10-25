//
//  BotEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

@Model
final class BotEntity {
    @Attribute(.unique) var id: String
    var name: String
    var botDescription: String
    var avatarURL: String
    var category: String
    var capabilitiesData: Data
    var model: String
    var systemPrompt: String
    var toolsData: Data
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        description: String,
        avatarURL: String,
        category: String = "general",
        capabilities: [String] = [],
        model: String = "gemini-1.5-flash",
        systemPrompt: String = "",
        tools: [String] = [],
        isActive: Bool = true,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.botDescription = description
        self.avatarURL = avatarURL
        self.category = category
        self.capabilitiesData = LocalJSONCoder.encode(capabilities)
        self.model = model
        self.systemPrompt = systemPrompt
        self.toolsData = LocalJSONCoder.encode(tools)
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var capabilities: [String] {
        get { LocalJSONCoder.decode(capabilitiesData, fallback: []) }
        set { capabilitiesData = LocalJSONCoder.encode(newValue) }
    }

    var tools: [String] {
        get { LocalJSONCoder.decode(toolsData, fallback: []) }
        set { toolsData = LocalJSONCoder.encode(newValue) }
    }
}
