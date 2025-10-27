//
//  ActionItemFormView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct ActionItemFormView: View {
    let conversationId: String
    let itemToEdit: ActionItemEntity?
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(FirestoreCoordinator.self) private var firestoreCoordinator

    @State private var task: String = ""
    @State private var priority: ActionItemPriority = .medium
    @State private var status: ActionItemStatus = .pending
    @State private var assignedTo: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(86400) // Tomorrow
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private var isEditMode: Bool {
        itemToEdit != nil
    }

    private var isValid: Bool {
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Task description", text: $task, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Priority", selection: $priority) {
                        ForEach([ActionItemPriority.low, .medium, .high, .urgent], id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }

                    Picker("Status", selection: $status) {
                        ForEach([ActionItemStatus.pending, .inProgress, .completed, .cancelled], id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }

                Section("Additional Details") {
                    TextField("Assigned to (optional)", text: $assignedTo)
                        .autocapitalization(.words)

                    Toggle("Set due date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Action Item" : "New Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "Save" : "Create") {
                        saveActionItem()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if let item = itemToEdit {
                    // Pre-populate form with existing data
                    task = item.task
                    priority = item.priority
                    status = item.status
                    assignedTo = item.assignedTo ?? ""
                    hasDueDate = item.dueDate != nil
                    dueDate = item.dueDate ?? Date().addingTimeInterval(86400)
                }
            }
        }
    }

    private func saveActionItem() {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssignedTo = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAssignedTo = trimmedAssignedTo.isEmpty ? nil : trimmedAssignedTo
        let finalDueDate = hasDueDate ? dueDate : nil

        Task {
            do {
                if let existing = itemToEdit {
                    // Update existing item
                    existing.task = trimmedTask
                    existing.priority = priority
                    existing.status = status
                    existing.assignedTo = finalAssignedTo
                    existing.dueDate = finalDueDate
                    existing.updatedAt = Date()

                    try modelContext.save()

                    // Sync to Firestore
                    try await firestoreCoordinator.updateActionItem(
                        conversationId: conversationId,
                        actionItemId: existing.id,
                        task: trimmedTask,
                        priority: priority,
                        status: status,
                        assignedTo: finalAssignedTo,
                        dueDate: finalDueDate
                    )
                } else {
                    // Create new item
                    let itemId = UUID().uuidString
                    let now = Date()

                    let newItem = ActionItemEntity(
                        id: itemId,
                        conversationId: conversationId,
                        task: trimmedTask,
                        assignedTo: finalAssignedTo,
                        dueDate: finalDueDate,
                        priority: priority,
                        status: status,
                        createdAt: now,
                        updatedAt: now
                    )

                    modelContext.insert(newItem)
                    try modelContext.save()

                    // Sync to Firestore
                    try await firestoreCoordinator.createActionItem(
                        conversationId: conversationId,
                        actionItemId: itemId,
                        task: trimmedTask,
                        priority: priority,
                        status: status,
                        assignedTo: finalAssignedTo,
                        dueDate: finalDueDate
                    )
                }

                await MainActor.run {
                    isSaving = false
                    onSave()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}
