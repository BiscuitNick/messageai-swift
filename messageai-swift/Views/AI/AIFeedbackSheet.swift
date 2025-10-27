//
//  AIFeedbackSheet.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI

/// Sheet for collecting user feedback on AI-generated content
struct AIFeedbackSheet: View {
    let conversationId: String
    let featureType: String
    let originalContent: String
    @Environment(AIFeaturesCoordinator.self) private var aiCoordinator
    @Environment(AuthCoordinator.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int = 0
    @State private var correction: String = ""
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("How would you rate this \(featureType)?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                rating = star
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundStyle(star <= rating ? .yellow : .gray)
                                    .font(.title2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Rating")
                }

                Section {
                    Text(originalContent)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("Original Content")
                }

                Section {
                    TextField("Enter your correction (optional)", text: $correction, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Suggested Correction")
                }

                Section {
                    TextField("Additional comments (optional)", text: $comment, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Comments")
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Provide Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitFeedback()
                    }
                    .disabled(isSubmitting || rating == 0)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        ProgressView("Submitting...")
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func submitFeedback() {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "User not authenticated"
            return
        }

        guard rating > 0 else {
            errorMessage = "Please provide a rating"
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let feedback = AIFeaturesCoordinator.AIFeedback(
                    userId: userId,
                    conversationId: conversationId,
                    featureType: featureType,
                    originalContent: originalContent,
                    userCorrection: correction.isEmpty ? nil : correction,
                    rating: rating,
                    comment: comment.isEmpty ? nil : comment
                )

                try await aiCoordinator.submitAIFeedback(feedback)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to submit feedback: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    AIFeedbackSheet(
        conversationId: "conv-123",
        featureType: "summary",
        originalContent: "Team discussed Q4 roadmap and decided to prioritize feature X for the upcoming release."
    )
    .environment(AIFeaturesCoordinator())
    .environment(AuthCoordinator())
}
