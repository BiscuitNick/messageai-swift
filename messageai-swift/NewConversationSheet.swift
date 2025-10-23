//
//  NewConversationSheet.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData

struct NewConversationSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case direct = "Direct"
        case group = "Group"
        case aiChat = "AI Chat"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .direct: return "New Message"
            case .group: return "New Group"
            case .aiChat: return "Chat with AI"
            }
        }
    }

    let currentUser: AuthService.AppUser
    let availableUsers: [UserEntity]
    let onCreated: (String) -> Void

    @Environment(MessagingService.self) private var messagingService
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode
    @State private var selectedParticipantIDs: Set<String>
    @State private var groupName: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""

    init(
        currentUser: AuthService.AppUser,
        availableUsers: [UserEntity],
        initialMode: Mode = .direct,
        onCreated: @escaping (String) -> Void
    ) {
        self.currentUser = currentUser
        self.availableUsers = availableUsers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.onCreated = onCreated
        _mode = State(initialValue: initialMode)
        _selectedParticipantIDs = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .group {
                    Section("Group Name") {
                        TextField("Team planning", text: $groupName)
                            .textInputAutocapitalization(.words)
                            .disabled(isCreating)
                    }
                }

                if mode == .aiChat {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI Assistant")
                                        .font(.headline)
                                    Text("Ask me anything!")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)

                            Text("I can help you with various tasks including answering questions, providing recommendations, drafting messages, and more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        TextField("Search", text: $searchText)
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .disabled(isCreating)
                    }

                    Section(header: Text("Participants")) {
                        if filteredUsers.isEmpty {
                            Text("No users found")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredUsers) { user in
                                Button {
                                    toggleSelection(for: user.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        ParticipantAvatar(initials: initials(for: user.displayName))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                                .foregroundStyle(.primary)
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        selectionIndicator(for: user.id)
                                    }
                                }
                                .disabled(isCreating)
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createConversation) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
            .interactiveDismissDisabled(isCreating)
            .alert(
                "Unable to create conversation",
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        errorMessage = nil
                    }
                },
                message: {
                    Text(errorMessage ?? "Unknown error")
                }
            )
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .direct {
                if let first = selectedParticipantIDs.first {
                    selectedParticipantIDs = [first]
                } else {
                    selectedParticipantIDs = []
                }
            }
        }
    }

    private var filteredUsers: [UserEntity] {
        guard !searchText.isEmpty else { return availableUsers }
        return availableUsers.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var canCreate: Bool {
        switch mode {
        case .direct:
            return selectedParticipantIDs.count == 1
        case .group:
            let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedParticipantIDs.count >= 2 && !trimmed.isEmpty
        case .aiChat:
            return true
        }
    }

    private func toggleSelection(for userId: String) {
        switch mode {
        case .direct:
            if selectedParticipantIDs.contains(userId) {
                selectedParticipantIDs.removeAll()
            } else {
                selectedParticipantIDs = [userId]
            }
        case .group:
            if selectedParticipantIDs.contains(userId) {
                selectedParticipantIDs.remove(userId)
            } else {
                selectedParticipantIDs.insert(userId)
            }
        case .aiChat:
            // No selection needed for AI chat
            break
        }
    }

    private func createConversation() {
        Task {
            isCreating = true
            defer { isCreating = false }

            do {
                let id: String

                switch mode {
                case .aiChat:
                    // Create conversation with AI bot
                    id = try await messagingService.createConversation(
                        with: ["messageai-bot"],
                        isGroup: false,
                        groupName: nil
                    )
                case .direct:
                    let participantIDs = Array(selectedParticipantIDs)
                    id = try await messagingService.createConversation(
                        with: participantIDs,
                        isGroup: false,
                        groupName: nil
                    )
                case .group:
                    let participantIDs = Array(selectedParticipantIDs)
                    let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    id = try await messagingService.createConversation(
                        with: participantIDs,
                        isGroup: true,
                        groupName: name
                    )
                }

                onCreated(id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectionIndicator(for userId: String) -> some View {
        let isSelected = selectedParticipantIDs.contains(userId)
        let symbol: String
        switch mode {
        case .direct:
            symbol = isSelected ? "largecircle.fill.circle" : "circle"
        case .group:
            symbol = isSelected ? "checkmark.circle.fill" : "circle"
        case .aiChat:
            symbol = "circle"
        }
        return Image(systemName: symbol)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .imageScale(.large)
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.prefix(2).joined()
    }
}

private struct ParticipantAvatar: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 36, height: 36)
    }
}
