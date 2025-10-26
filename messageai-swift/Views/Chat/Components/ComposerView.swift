//
//  ComposerView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-25.
//

import SwiftUI

struct ComposerView: View {
    @Binding var messageText: String
    let isSending: Bool
    let sendAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button(action: sendAction) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
            }
            .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}
