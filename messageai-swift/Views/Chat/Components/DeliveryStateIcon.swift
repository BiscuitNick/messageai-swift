//
//  DeliveryStateIcon.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct DeliveryStateIcon: View {
    let state: MessageDeliveryState
    let onRetry: (() -> Void)?
    var color: Color

    var body: some View {
        switch state {
        case .pending:
            // Animated gray checkmark
            Image(systemName: "checkmark")
                .foregroundStyle(.gray)
                .opacity(0.6)
                .symbolEffect(.pulse)
        case .sent:
            // Single blue checkmark
            Image(systemName: "checkmark")
                .foregroundStyle(.blue)
        case .delivered:
            // Double blue checkmark (regular weight)
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        case .read:
            // Double blue checkmark (bold)
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.bold)
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.bold)
            }
        case .failed:
            // Red exclamation with retry
            if let onRetry {
                Button(action: onRetry) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sending message")
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}
