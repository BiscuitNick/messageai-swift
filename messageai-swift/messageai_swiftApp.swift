//
//  messageai_swiftApp.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
struct messageai_swiftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authService: AuthService
    @State private var firestoreService: FirestoreService
    @State private var messagingService: MessagingService
    @State private var notificationService: NotificationService
    @State private var networkMonitor: NetworkMonitor
    @State private var aiFeaturesService: AIFeaturesService
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserEntity.self,
            BotEntity.self,
            ConversationEntity.self,
            MessageEntity.self,
            ThreadSummaryEntity.self,
            ActionItemEntity.self,
            SearchResultEntity.self,
            RecentQueryEntity.self,
            DecisionEntity.self,
            MeetingSuggestionEntity.self,
            SchedulingSuggestionSnoozeEntity.self,
            CoordinationInsightEntity.self,
            ProactiveAlertEntity.self,
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
        let notification = NotificationService()
        // Note: NotificationService.configure() is called in ContentView after AIFeaturesService is available
        _firestoreService = State(wrappedValue: firestore)
        _authService = State(wrappedValue: AuthService())
        _messagingService = State(wrappedValue: MessagingService())
        _notificationService = State(wrappedValue: notification)
        _networkMonitor = State(wrappedValue: NetworkMonitor())
        _aiFeaturesService = State(wrappedValue: AIFeaturesService())
        appDelegate.notificationService = notification
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(firestoreService)
                .environment(messagingService)
                .environment(notificationService)
                .environment(networkMonitor)
                .environment(aiFeaturesService)
        }
        .modelContainer(sharedModelContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    var notificationService: NotificationService?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        notificationService?.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications:", error.localizedDescription)
    }
}
