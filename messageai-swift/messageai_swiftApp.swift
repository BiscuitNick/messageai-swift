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
        _authService = State(wrappedValue: AuthService())
        _firestoreService = State(wrappedValue: FirestoreService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(firestoreService)
        }
        .modelContainer(sharedModelContainer)
    }
}
