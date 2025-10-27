//
//  DecisionsTabView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData

struct DecisionsTabView: View {
    let conversationId: String

    @Environment(AIFeaturesCoordinator.self) private var aiCoordinator
    @Environment(\.modelContext) private var modelContext

    @Query private var decisions: [DecisionEntity]

    @State private var isTracking: Bool = false
    @State private var selectedStatus: DecisionFollowUpStatus? = nil
    @State private var showingCreateForm: Bool = false
    @State private var decisionToEdit: DecisionEntity? = nil

    init(conversationId: String) {
        self.conversationId = conversationId
        _decisions = Query(
            filter: #Predicate<DecisionEntity> { decision in
                decision.conversationId == conversationId
            },
            sort: [
                SortDescriptor(\DecisionEntity.decidedAt, order: .reverse)
            ]
        )
    }

    private var groupedDecisions: [(status: DecisionFollowUpStatus, items: [DecisionEntity])] {
        let filtered = selectedStatus == nil ? decisions : decisions.filter { $0.followUpStatus == selectedStatus }

        let groups = Dictionary(grouping: filtered) { $0.followUpStatus }
        let statusOrder: [DecisionFollowUpStatus] = [.pending, .completed, .cancelled]

        return statusOrder.compactMap { status in
            guard let items = groups[status], !items.isEmpty else { return nil }
            return (status: status, items: items)
        }
    }

    private var statusCounts: [DecisionFollowUpStatus: Int] {
        Dictionary(grouping: decisions) { $0.followUpStatus }
            .mapValues { $0.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status filter picker
            if !decisions.isEmpty {
                Picker("Filter", selection: $selectedStatus) {
                    Text("All (\(decisions.count))").tag(nil as DecisionFollowUpStatus?)
                    ForEach([DecisionFollowUpStatus.pending, .completed, .cancelled], id: \.self) { status in
                        if let count = statusCounts[status], count > 0 {
                            Text("\(status.displayLabel) (\(count))").tag(status as DecisionFollowUpStatus?)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            // Content
            if isTracking {
                loadingView
            } else if decisions.isEmpty {
                emptyView
            } else {
                decisionsList
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
            DecisionFormView(
                conversationId: conversationId,
                decisionToEdit: nil,
                onSave: {
                    showingCreateForm = false
                },
                onCancel: {
                    showingCreateForm = false
                }
            )
        }
        .sheet(item: $decisionToEdit) { decision in
            DecisionFormView(
                conversationId: conversationId,
                decisionToEdit: decision,
                onSave: {
                    decisionToEdit = nil
                },
                onCancel: {
                    decisionToEdit = nil
                }
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Tracking decisions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Decisions")
                .font(.headline)
            Text("Track decisions made in this conversation to follow up on commitments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Track Decisions") {
                recordDecisions()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var decisionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedDecisions, id: \.status) { group in
                    Section {
                        ForEach(group.items) { decision in
                            DecisionRow(
                                decision: decision,
                                conversationId: conversationId,
                                onEdit: {
                                    decisionToEdit = decision
                                }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                        }
                    } header: {
                        HStack {
                            Text(group.status.displayLabel)
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
                    recordDecisions()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Decisions")
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
    }

    private func recordDecisions() {
        isTracking = true
        Task {
            do {
                _ = try await aiCoordinator.decisionTrackingService.recordDecisions(
                    conversationId: conversationId,
                    windowDays: 30
                )
            } catch {
                print("[DecisionsTabView] Failed to record: \(error)")
            }
            isTracking = false
        }
    }
}

private struct DecisionRow: View {
    let decision: DecisionEntity
    let conversationId: String
    let onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AIFeaturesCoordinator.self) private var aiCoordinator
    @Environment(NotificationCoordinator.self) private var notificationService
    @Environment(FirestoreCoordinator.self) private var firestoreCoordinator

    @State private var showingReminderPicker = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status checkbox button (inline, like action items)
            Button {
                toggleStatus()
            } label: {
                Image(systemName: decision.followUpStatus == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(decision.followUpStatus.color)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                // Decision text
                Text(decision.decisionText)
                    .font(.body.weight(.medium))
                    .strikethrough(decision.followUpStatus == .completed)
                    .foregroundStyle(decision.followUpStatus == .completed ? .secondary : .primary)

                // Context summary
                if !decision.contextSummary.isEmpty {
                    Text(decision.contextSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Metadata row
                HStack(spacing: 12) {
                    // Decided at
                    Label {
                        Text(decision.decidedAt, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Reminder indicator
                    if let reminderDate = decision.reminderDate {
                        Label {
                            Text(reminderDate, style: .date)
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    // Confidence score
                    Label {
                        Text("\(Int(decision.confidenceScore * 100))%")
                    } icon: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    // Status badge
                    statusBadge
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

            Divider()

            // Status options
            Menu {
                Button {
                    setStatus(.pending)
                } label: {
                    Label("Pending", systemImage: decision.followUpStatus == .pending ? "checkmark" : "circle")
                }

                Button {
                    setStatus(.completed)
                } label: {
                    Label("Completed", systemImage: decision.followUpStatus == .completed ? "checkmark" : "checkmark.circle")
                }

                Button {
                    setStatus(.cancelled)
                } label: {
                    Label("Cancelled", systemImage: decision.followUpStatus == .cancelled ? "checkmark" : "xmark.circle")
                }
            } label: {
                Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button {
                showingReminderPicker = true
            } label: {
                Label(
                    decision.reminderDate == nil ? "Set Reminder" : "Change Reminder",
                    systemImage: "bell"
                )
            }

            if decision.reminderDate != nil {
                Button {
                    removeReminder()
                } label: {
                    Label("Remove Reminder", systemImage: "bell.slash")
                }
            }

            Divider()

            Button(role: .destructive) {
                deleteDecision()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingReminderPicker) {
            ReminderPickerView(
                decision: decision,
                onSave: { date in
                    setReminder(date: date)
                    showingReminderPicker = false
                },
                onCancel: {
                    showingReminderPicker = false
                }
            )
        }
    }

    private var statusBadge: some View {
        Text(decision.followUpStatus.displayLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(decision.followUpStatus.color.opacity(0.2))
            .foregroundStyle(decision.followUpStatus.color)
            .clipShape(Capsule())
    }

    private func setReminder(date: Date) {
        // Update in SwiftData
        decision.reminderDate = date
        decision.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("[DecisionRow] Failed to save reminder: \(error)")
        }

        // Schedule notification and sync to Firestore
        Task {
            do {
                try await notificationService.scheduleDecisionReminder(
                    decisionId: decision.id,
                    conversationId: conversationId,
                    decisionText: decision.decisionText,
                    reminderDate: date
                )

                try await firestoreCoordinator.updateDecisionReminder(
                    conversationId: conversationId,
                    decisionId: decision.id,
                    reminderDate: date
                )
            } catch {
                print("[DecisionRow] Failed to schedule reminder: \(error)")
            }
        }
    }

    private func removeReminder() {
        // Cancel notification
        notificationService.cancelDecisionReminder(decisionId: decision.id)

        // Update in SwiftData
        decision.reminderDate = nil
        decision.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("[DecisionRow] Failed to remove reminder: \(error)")
        }

        // Sync to Firestore
        Task {
            do {
                try await firestoreCoordinator.updateDecisionReminder(
                    conversationId: conversationId,
                    decisionId: decision.id,
                    reminderDate: nil
                )
            } catch {
                print("[DecisionRow] Failed to sync reminder removal: \(error)")
            }
        }
    }

    /// Toggle status between pending and completed (for inline checkbox)
    private func toggleStatus() {
        // Toggle between pending and completed
        let newStatus: DecisionFollowUpStatus = decision.followUpStatus == .completed ? .pending : .completed
        setStatus(newStatus)
    }

    /// Set decision status to a specific value
    private func setStatus(_ newStatus: DecisionFollowUpStatus) {
        // Cancel reminder if marking as completed or cancelled
        if newStatus == .completed || newStatus == .cancelled {
            if decision.reminderDate != nil {
                notificationService.cancelDecisionReminder(decisionId: decision.id)
                decision.reminderDate = nil
            }
        }

        // Update in SwiftData
        decision.followUpStatus = newStatus
        decision.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("[DecisionRow] Failed to save status: \(error)")
        }

        // Sync back to Firestore
        Task {
            do {
                try await aiCoordinator.decisionTrackingService.updateDecisionStatus(
                    conversationId: conversationId,
                    decisionId: decision.id,
                    followUpStatus: newStatus
                )
            } catch {
                print("[DecisionRow] Failed to sync status to Firestore: \(error)")
            }
        }
    }

    private func deleteDecision() {
        // Cancel any pending reminder
        if decision.reminderDate != nil {
            notificationService.cancelDecisionReminder(decisionId: decision.id)
        }

        // Delete from SwiftData
        modelContext.delete(decision)

        do {
            try modelContext.save()
        } catch {
            print("[DecisionRow] Failed to delete from SwiftData: \(error)")
        }

        // Delete from Firestore
        Task {
            do {
                try await aiCoordinator.decisionTrackingService.deleteDecision(
                    conversationId: conversationId,
                    decisionId: decision.id
                )
            } catch {
                print("[DecisionRow] Failed to delete from Firestore: \(error)")
            }
        }
    }
}

// MARK: - Reminder Picker

private struct ReminderPickerView: View {
    let decision: DecisionEntity
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var selectedDate: Date

    init(decision: DecisionEntity, onSave: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.decision = decision
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize with existing reminder date or tomorrow at 9 AM
        let initial: Date
        if let existing = decision.reminderDate {
            initial = existing
        } else {
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            initial = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        _selectedDate = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Reminder Date",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }

                Section {
                    Text("You'll be notified to follow up on this decision.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedDate)
                    }
                }
            }
        }
    }
}
