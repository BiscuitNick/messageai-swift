//
//  ActionItemsTabView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData

struct ActionItemsTabView: View {
    let conversationId: String

    @Environment(AIFeaturesService.self) private var aiFeaturesService
    @Environment(\.modelContext) private var modelContext

    @Query private var actionItems: [ActionItemEntity]

    @State private var isExtracting: Bool = false
    @State private var selectedStatus: ActionItemStatus? = nil
    @State private var showingCreateForm: Bool = false
    @State private var itemToEdit: ActionItemEntity? = nil

    init(conversationId: String) {
        self.conversationId = conversationId
        _actionItems = Query(
            filter: #Predicate<ActionItemEntity> { item in
                item.conversationId == conversationId
            },
            sort: [
                SortDescriptor(\ActionItemEntity.priorityRawValue, order: .reverse),
                SortDescriptor(\ActionItemEntity.createdAt, order: .reverse)
            ]
        )
    }

    private var groupedItems: [(status: ActionItemStatus, items: [ActionItemEntity])] {
        let filtered = selectedStatus == nil ? actionItems : actionItems.filter { $0.status == selectedStatus }

        let groups = Dictionary(grouping: filtered) { $0.status }
        let statusOrder: [ActionItemStatus] = [.pending, .inProgress, .completed, .cancelled]

        return statusOrder.compactMap { status in
            guard let items = groups[status], !items.isEmpty else { return nil }
            return (status: status, items: items)
        }
    }

    private var statusCounts: [ActionItemStatus: Int] {
        Dictionary(grouping: actionItems) { $0.status }
            .mapValues { $0.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status filter picker
            if !actionItems.isEmpty {
                Picker("Filter", selection: $selectedStatus) {
                    Text("All (\(actionItems.count))").tag(nil as ActionItemStatus?)
                    ForEach([ActionItemStatus.pending, .inProgress, .completed, .cancelled], id: \.self) { status in
                        if let count = statusCounts[status], count > 0 {
                            Text("\(status.displayName) (\(count))").tag(status as ActionItemStatus?)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            // Content
            if aiFeaturesService.actionItemsLoadingStates[conversationId] == true || isExtracting {
                loadingView
            } else if let error = aiFeaturesService.actionItemsErrors[conversationId] {
                errorView(error)
            } else if actionItems.isEmpty {
                emptyView
            } else {
                itemsList
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateForm) {
            ActionItemFormView(
                conversationId: conversationId,
                itemToEdit: nil,
                onSave: {
                    showingCreateForm = false
                },
                onCancel: {
                    showingCreateForm = false
                }
            )
        }
        .sheet(item: $itemToEdit) { item in
            ActionItemFormView(
                conversationId: conversationId,
                itemToEdit: item,
                onSave: {
                    itemToEdit = nil
                },
                onCancel: {
                    itemToEdit = nil
                }
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Extracting action items...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to extract action items")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                extractActionItems()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Action Items")
                .font(.headline)
            Text("Extract action items from this conversation to track tasks and to-dos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Extract Action Items") {
                extractActionItems()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedItems, id: \.status) { group in
                    Section {
                        ForEach(group.items) { item in
                            ActionItemRow(
                                item: item,
                                conversationId: conversationId,
                                onEdit: {
                                    itemToEdit = item
                                }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground))
                        }
                    } header: {
                        HStack {
                            Text(group.status.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))
                    }
                }

                // Refresh button at bottom
                Button {
                    extractActionItems()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Action Items")
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }

    private func extractActionItems() {
        isExtracting = true
        Task {
            do {
                _ = try await aiFeaturesService.extractActionItems(
                    conversationId: conversationId,
                    forceRefresh: true
                )
            } catch {
                print("[ActionItemsTabView] Failed to extract: \(error)")
            }
            isExtracting = false
        }
    }
}

private struct ActionItemRow: View {
    let item: ActionItemEntity
    let conversationId: String
    let onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(FirestoreService.self) private var firestoreService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status checkbox
            Button {
                toggleStatus()
            } label: {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Task text
                Text(item.task)
                    .font(.body)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)

                // Metadata
                HStack(spacing: 8) {
                    // Priority badge
                    priorityBadge

                    // Due date if present
                    if let dueDate = item.dueDate {
                        Label {
                            Text(dueDate, style: .date)
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    // Assigned to if present
                    if let assignedTo = item.assignedTo {
                        Label {
                            Text(assignedTo)
                        } icon: {
                            Image(systemName: "person")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteItem()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var priorityBadge: some View {
        Text(item.priority.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundStyle(priorityColor)
            .clipShape(Capsule())
    }

    private var priorityColor: Color {
        switch item.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }

    private func toggleStatus() {
        // Toggle between pending and completed
        let newStatus: ActionItemStatus = item.status == .completed ? .pending : .completed
        item.status = newStatus
        item.updatedAt = Date()

        // Save to SwiftData
        do {
            try modelContext.save()
        } catch {
            print("[ActionItemRow] Failed to save status: \(error)")
        }

        // Sync back to Firestore
        Task {
            do {
                try await firestoreService.updateActionItem(
                    conversationId: conversationId,
                    actionItemId: item.id,
                    task: item.task,
                    priority: item.priority,
                    status: newStatus,
                    assignedTo: item.assignedTo,
                    dueDate: item.dueDate
                )
            } catch {
                print("[ActionItemRow] Failed to sync status to Firestore: \(error)")
            }
        }
    }

    private func deleteItem() {
        // Delete from SwiftData
        modelContext.delete(item)

        do {
            try modelContext.save()
        } catch {
            print("[ActionItemRow] Failed to delete from SwiftData: \(error)")
        }

        // Delete from Firestore
        Task {
            do {
                try await firestoreService.deleteActionItem(
                    conversationId: conversationId,
                    actionItemId: item.id
                )
            } catch {
                print("[ActionItemRow] Failed to delete from Firestore: \(error)")
            }
        }
    }
}

// MARK: - Display Extensions

extension ActionItemStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

extension ActionItemPriority {
    var displayName: String {
        switch self {
        case .urgent: return "Urgent"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}
