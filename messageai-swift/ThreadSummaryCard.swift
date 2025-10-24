//
//  ThreadSummaryCard.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI

/// Card view displaying an AI-generated conversation summary
struct ThreadSummaryCard: View {
    let summary: ThreadSummaryResponse?
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Thread Summary", systemImage: "text.bubble")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isLoading)
                }
            }

            if let error = error {
                // Error state
                VStack(alignment: .leading, spacing: 8) {
                    Label("Failed to load summary", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: onRefresh) {
                        Text("Try Again")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let summary = summary {
                // Summary content
                VStack(alignment: .leading, spacing: 12) {
                    // Summary text
                    Text(summary.summary)
                        .font(.body)
                        .foregroundStyle(.primary)

                    // Metadata
                    HStack(spacing: 12) {
                        Label("\(summary.messageCount) messages", systemImage: "message")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(formatTimestamp(summary.timestamp), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Key points (expandable)
                    if !summary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: { isExpanded.toggle() }) {
                                HStack {
                                    Text("Key Points (\(summary.keyPoints.count))")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if isExpanded {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { index, point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text(point)
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } else if isLoading {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generating summary...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No summary available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: onRefresh) {
                        Text("Generate Summary")
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    VStack(spacing: 20) {
        // Preview with summary
        ThreadSummaryCard(
            summary: ThreadSummaryResponse(
                summary: "Team discussed Q4 roadmap and decided to prioritize feature X for the upcoming release.",
                keyPoints: [
                    "Roadmap review completed",
                    "Feature X prioritized",
                    "Budget approved for Q4",
                ],
                conversationId: "conv-123",
                timestamp: Date().addingTimeInterval(-3600),
                messageCount: 42
            ),
            isLoading: false,
            error: nil,
            onRefresh: {}
        )
        .padding()

        // Preview loading
        ThreadSummaryCard(
            summary: nil,
            isLoading: true,
            error: nil,
            onRefresh: {}
        )
        .padding()

        // Preview error
        ThreadSummaryCard(
            summary: nil,
            isLoading: false,
            error: "Network connection failed",
            onRefresh: {}
        )
        .padding()
    }
}
