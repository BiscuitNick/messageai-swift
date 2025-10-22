//
//  messageai_swiftApp.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct messageai_swiftApp: App {
    @State private var authService: AuthService
    @State private var firestoreService: FirestoreService
    @State private var messagingService: MessagingService
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserEntity.self,
            ConversationEntity.self,
            MessageEntity.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        FirebaseApp.configure()
        let firestore = FirestoreService()
        _firestoreService = State(wrappedValue: firestore)
        _authService = State(wrappedValue: AuthService())
        _messagingService = State(wrappedValue: MessagingService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(firestoreService)
                .environment(messagingService)
        }
        .modelContainer(sharedModelContainer)
    }
}
