//
//  MeetingSuggestionsPanel.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI

struct MeetingSuggestionsPanel: View {
    let suggestions: MeetingSuggestionsResponse?
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onCopy: (MeetingTimeSuggestion) -> Void
    let onShare: (MeetingTimeSuggestion) -> Void
    let onAddToCalendar: (MeetingTimeSuggestion) -> Void
    let onDismiss: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Smart Meeting Suggestions", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))

            if isExpanded {
                Divider()

                // Content
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if let error = error {
                            ErrorCard(error: error, onRetry: onRefresh)
                        } else if let response = suggestions {
                            ForEach(Array(response.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                MeetingSuggestionCard(
                                    suggestion: suggestion,
                                    rank: index + 1,
                                    onCopy: { onCopy(suggestion) },
                                    onShare: { onShare(suggestion) },
                                    onAddToCalendar: { onAddToCalendar(suggestion) }
                                )
                            }
                        } else if !isLoading {
                            EmptyStateCard(onRefresh: onRefresh)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 280)
                .background(Color(.systemGroupedBackground))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
    }
}

struct MeetingSuggestionCard: View {
    let suggestion: MeetingTimeSuggestion
    let rank: Int
    let onCopy: () -> Void
    let onShare: () -> Void
    let onAddToCalendar: () -> Void

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: suggestion.startTime)
    }

    private var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: suggestion.endTime)
    }

    private var scoreColor: Color {
        if suggestion.score >= 0.8 { return .green }
        if suggestion.score >= 0.6 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rank badge and score
            HStack {
                ZStack {
                    Circle()
                        .fill(scoreColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("#\(rank)")
                        .font(.caption.bold())
                        .foregroundStyle(scoreColor)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                    Text(String(format: "%.0f%%", suggestion.score * 100))
                        .font(.caption.bold())
                }
                .foregroundStyle(scoreColor)
            }

            // Day and time
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: suggestion.timeOfDay.systemImage)
                        .font(.caption)
                    Text(suggestion.dayOfWeek)
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.primary)

                Text("\(formattedStartTime) - \(formattedEndTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Justification
            Text(suggestion.justification)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Actions
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }

                    Button(action: onShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(8)
                    }
                }

                Button(action: onAddToCalendar) {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .foregroundStyle(.green)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(width: 260)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct ErrorCard: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)

            Text("Failed to load suggestions")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 260)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct EmptyStateCard: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No suggestions yet")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Tap to get AI-powered meeting time suggestions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button(action: onRefresh) {
                Label("Get Suggestions", systemImage: "sparkles")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 260)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// Extension to add system image for TimeOfDay
extension TimeOfDay {
    var systemImage: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        }
    }
}

// MARK: - Preview
#if DEBUG
#Preview("With Suggestions") {
    MeetingSuggestionsPanel(
        suggestions: MeetingSuggestionsResponse(
            suggestions: [
                MeetingTimeSuggestion(
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    score: 0.9,
                    justification: "Peak activity time based on historical patterns",
                    dayOfWeek: "Friday",
                    timeOfDay: .afternoon
                ),
                MeetingTimeSuggestion(
                    startTime: Date().addingTimeInterval(86400),
                    endTime: Date().addingTimeInterval(86400 + 3600),
                    score: 0.75,
                    justification: "Good alternative slot with moderate availability",
                    dayOfWeek: "Monday",
                    timeOfDay: .morning
                ),
            ],
            conversationId: "conv-123",
            durationMinutes: 60,
            participantCount: 3,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        ),
        isLoading: false,
        error: nil,
        onRefresh: {},
        onCopy: { _ in },
        onShare: { _ in },
        onAddToCalendar: { _ in },
        onDismiss: {}
    )
    .padding()
}

#Preview("Loading") {
    MeetingSuggestionsPanel(
        suggestions: nil,
        isLoading: true,
        error: nil,
        onRefresh: {},
        onCopy: { _ in },
        onShare: { _ in },
        onAddToCalendar: { _ in },
        onDismiss: {}
    )
    .padding()
}

#Preview("Error") {
    MeetingSuggestionsPanel(
        suggestions: nil,
        isLoading: false,
        error: "Network connection failed",
        onRefresh: {},
        onCopy: { _ in },
        onShare: { _ in },
        onAddToCalendar: { _ in },
        onDismiss: {}
    )
    .padding()
}

#Preview("Empty") {
    MeetingSuggestionsPanel(
        suggestions: nil,
        isLoading: false,
        error: nil,
        onRefresh: {},
        onCopy: { _ in },
        onShare: { _ in },
        onAddToCalendar: { _ in },
        onDismiss: {}
    )
    .padding()
}
#endif
