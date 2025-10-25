//
//  ActionItemEntity.swift
//  messageai-swift
//
//  Split from Models.swift on 10/24/25.
//

import Foundation
import SwiftData

@Model
final class ActionItemEntity {
    @Attribute(.unique) var id: String
    var conversationId: String
    var task: String
    var assignedTo: String?
    var dueDate: Date?
    var priorityRawValue: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        conversationId: String,
        task: String,
        assignedTo: String? = nil,
        dueDate: Date? = nil,
        priority: ActionItemPriority = .medium,
        status: ActionItemStatus = .pending,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.task = task
        self.assignedTo = assignedTo
        self.dueDate = dueDate
        self.priorityRawValue = priority.rawValue
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var priority: ActionItemPriority {
        get { ActionItemPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    var status: ActionItemStatus {
        get { ActionItemStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }
}
