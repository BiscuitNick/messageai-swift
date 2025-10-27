//
//  BotSyncService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData
import FirebaseFirestore

/// Service responsible for real-time bot synchronization from Firestore to SwiftData
@MainActor
final class BotSyncService {

    // MARK: - Properties

    private let db: Firestore
    private weak var modelContext: ModelContext?
    private var listenerManager: FirestoreListenerManager?

    // MARK: - Initialization

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func configure(listenerManager: FirestoreListenerManager) {
        self.listenerManager = listenerManager
    }

    // MARK: - Public API

    /// Start observing bots collection
    /// - Parameter modelContext: SwiftData model context
    func startBotListener(modelContext: ModelContext) {
        self.modelContext = modelContext

        let listenerId = "bots"
        listenerManager?.remove(id: listenerId)

        let listener = db.collection("bots")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.debugLog("Bot listener error: \(error.localizedDescription)")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleBotSnapshot(snapshot, modelContext: modelContext)
                }
            }

        listenerManager?.register(id: listenerId, listener: listener)

        #if DEBUG
        print("[BotSyncService] Started bot listener")
        #endif
    }

    /// Stop observing bots collection
    func stopBotListener() {
        listenerManager?.remove(id: "bots")
        modelContext = nil

        #if DEBUG
        print("[BotSyncService] Stopped bot listener")
        #endif
    }

    // MARK: - Private Helpers

    /// Handle bot snapshot updates
    private func handleBotSnapshot(_ snapshot: QuerySnapshot?, modelContext: ModelContext) async {
        guard let snapshot else {
            debugLog("Bot snapshot is nil")
            return
        }

        debugLog("Bot snapshot received with \(snapshot.documentChanges.count) changes")

        for change in snapshot.documentChanges {
            let data = change.document.data()
            let botId = change.document.documentID

            debugLog("Bot change type: \(change.type.rawValue) for botId: \(botId)")

            var descriptor = FetchDescriptor<BotEntity>(
                predicate: #Predicate<BotEntity> { bot in
                    bot.id == botId
                }
            )
            descriptor.fetchLimit = 1

            let name = data["name"] as? String ?? "AI Assistant"
            let description = data["description"] as? String ?? ""
            let avatarURL = data["avatarURL"] as? String ?? ""
            let category = data["category"] as? String ?? "general"
            let capabilities = data["capabilities"] as? [String] ?? []
            let model = data["model"] as? String ?? "gemini-1.5-flash"
            let systemPrompt = data["systemPrompt"] as? String ?? ""
            let tools = data["tools"] as? [String] ?? []
            let isActive = data["isActive"] as? Bool ?? true
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

            switch change.type {
            case .added, .modified:
                if let existing = try? modelContext.fetch(descriptor).first {
                    debugLog("Updating existing bot: \(botId)")
                    existing.name = name
                    existing.botDescription = description
                    existing.avatarURL = avatarURL
                    existing.category = category
                    existing.capabilities = capabilities
                    existing.model = model
                    existing.systemPrompt = systemPrompt
                    existing.tools = tools
                    existing.isActive = isActive
                    existing.updatedAt = updatedAt
                } else {
                    debugLog("Creating new bot: \(botId) with name: \(name)")
                    let newBot = BotEntity(
                        id: botId,
                        name: name,
                        description: description,
                        avatarURL: avatarURL,
                        category: category,
                        capabilities: capabilities,
                        model: model,
                        systemPrompt: systemPrompt,
                        tools: tools,
                        isActive: isActive,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newBot)
                }
            case .removed:
                debugLog("Removing bot: \(botId)")
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        }

        do {
            try modelContext.save()
            debugLog("Bots persisted successfully")
        } catch {
            debugLog("Failed to persist bots: \(error.localizedDescription)")
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[BotSyncService]", message)
        #endif
    }
}
