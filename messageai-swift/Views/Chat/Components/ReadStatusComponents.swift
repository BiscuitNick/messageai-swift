//
//  ReadStatusComponents.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct ReadStatusEntry: Identifiable {
    let id: String
    let displayName: String
    let initials: String
    let isSender: Bool
    let isSelf: Bool
    let isComplete: Bool
    let statusText: String
    let color: Color
}

struct ReadStatusPopover: View {
    let entries: [ReadStatusEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.count > 1 {
                Text("Read Receipts")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(entry.color)
                            .opacity(entry.isComplete ? 1 : 0.2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.footnote.weight(.semibold))
                            Text(entry.statusText)
                                .font(.caption2)
                                .foregroundStyle(entry.isComplete ? .secondary : Color.secondary.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}
