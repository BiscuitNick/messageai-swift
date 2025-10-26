//
//  SchedulingIntentBanner.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct SchedulingIntentBanner: View {
    let confidence: Double
    let onViewSuggestions: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    private var confidenceText: String {
        if confidence >= 0.8 {
            return "High confidence"
        } else if confidence >= 0.6 {
            return "Medium confidence"
        } else {
            return "Detected"
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .blue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(confidenceColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18))
                        .foregroundStyle(confidenceColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduling Intent Detected")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text(confidenceText)
                            .font(.caption)
                    }
                    .foregroundStyle(confidenceColor)
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onSnooze) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("Snooze 1h")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.secondary)
                    .cornerRadius(8)
                }

                Button(action: onViewSuggestions) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text("View Suggestions")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(confidenceColor)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
