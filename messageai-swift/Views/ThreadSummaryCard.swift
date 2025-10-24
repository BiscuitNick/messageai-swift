//
//  ThreadSummaryCard.swift
//  messageai-swift
//
//  Created by Claude Code on 10/23/25.
//

import SwiftUI

struct ThreadSummaryCard: View {
    let summary: ThreadSummaryResponse
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thread Summary")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(summary.messageCount) messages · \(formattedDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Summary content
            ScrollView {
                Text(summary.summary)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: isExpanded ? 300 : 120)

            // Expand/Collapse button
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.subheadline)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: onSave) {
                    Label("Save Summary", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding()
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: summary.generatedAt, relativeTo: Date())
    }
}

struct ThreadSummaryLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Generating summary...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding()
    }
}

struct ThreadSummaryErrorView: View {
    let error: Error
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Failed to Generate Summary")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDismiss) {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding()
    }
}
