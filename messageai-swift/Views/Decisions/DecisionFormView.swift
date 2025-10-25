//
//  DecisionFormView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData
import FirebaseFirestore

struct DecisionFormView: View {
    let conversationId: String
    let decisionToEdit: DecisionEntity?
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(FirestoreService.self) private var firestoreService

    @State private var decisionText: String = ""
    @State private var contextSummary: String = ""
    @State private var followUpStatus: DecisionFollowUpStatus = .pending
    @State private var decidedAt: Date = Date()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private var isEditMode: Bool {
        decisionToEdit != nil
    }

    private var isValid: Bool {
        !decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Decision") {
                    TextField("Decision text", text: $decisionText, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Context (optional)", text: $contextSummary, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Details") {
                    DatePicker("Decided on", selection: $decidedAt, displayedComponents: .date)

                    Picker("Follow-up status", selection: $followUpStatus) {
                        ForEach([DecisionFollowUpStatus.pending, .completed, .cancelled], id: \.self) { status in
                            Text(status.displayLabel).tag(status)
                        }
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
            .navigationTitle(isEditMode ? "Edit Decision" : "New Decision")
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
                        saveDecision()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if let decision = decisionToEdit {
                    // Pre-populate form with existing data
                    decisionText = decision.decisionText
                    contextSummary = decision.contextSummary
                    followUpStatus = decision.followUpStatus
                    decidedAt = decision.decidedAt
                }
            }
        }
    }

    private func saveDecision() {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        let trimmedDecisionText = decisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = contextSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if let existing = decisionToEdit {
                    // Update existing decision
                    existing.decisionText = trimmedDecisionText
                    existing.contextSummary = trimmedContext
                    existing.followUpStatus = followUpStatus
                    existing.decidedAt = decidedAt
                    existing.updatedAt = Date()

                    try modelContext.save()

                    // Sync to Firestore
                    try await firestoreService.updateDecision(
                        conversationId: conversationId,
                        decisionId: existing.id,
                        decisionText: trimmedDecisionText,
                        contextSummary: trimmedContext,
                        decidedAt: decidedAt,
                        followUpStatus: followUpStatus
                    )
                } else {
                    // Create new decision
                    let decisionId = UUID().uuidString
                    let now = Date()

                    let newDecision = DecisionEntity(
                        id: decisionId,
                        conversationId: conversationId,
                        decisionText: trimmedDecisionText,
                        contextSummary: trimmedContext,
                        participantIds: [], // Empty for manual entries
                        decidedAt: decidedAt,
                        followUpStatus: followUpStatus,
                        confidenceScore: 1.0, // Manual entries have full confidence
                        reminderDate: nil,
                        createdAt: now,
                        updatedAt: now
                    )

                    modelContext.insert(newDecision)
                    try modelContext.save()

                    // Sync to Firestore
                    try await firestoreService.createDecision(
                        conversationId: conversationId,
                        decisionId: decisionId,
                        decisionText: trimmedDecisionText,
                        contextSummary: trimmedContext,
                        participantIds: [],
                        decidedAt: decidedAt,
                        followUpStatus: followUpStatus,
                        confidenceScore: 1.0
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
