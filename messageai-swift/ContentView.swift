//
//  ContentView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import Observation
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(MessagingService.self) private var messagingService
    @Environment(\.modelContext) private var modelContext
    @State private var hasConfiguredContext = false

    var body: some View {
        Group {
            if let user = authService.currentUser {
                ConversationsRootView(currentUser: user)
            } else {
                AuthView()
            }
        }
        .task {
            guard !hasConfiguredContext else { return }
            authService.configure(modelContext: modelContext, firestoreService: firestoreService)
            if let userId = authService.currentUser?.id {
                messagingService.configure(modelContext: modelContext, currentUserId: userId)
            }
            hasConfiguredContext = true
        }
        .onChange(of: authService.currentUser?.id) { _, newId in
            guard let newId else {
                messagingService.reset()
                return
            }
                messagingService.configure(modelContext: modelContext, currentUserId: newId)
        }
    }
}
