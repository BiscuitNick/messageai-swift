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
    @State private var authService: AuthCoordinator
    @State private var firestoreCoordinator: FirestoreCoordinator
    @State private var messagingCoordinator: MessagingCoordinator
    @State private var notificationService: NotificationCoordinator
    @State private var networkMonitor: NetworkMonitor
    @State private var aiCoordinator: AIFeaturesCoordinator
    @State private var typingStatusService: TypingStatusService
    @State private var networkSimulator: NetworkSimulator
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
        let firestore = FirestoreCoordinator()
        let notification = NotificationCoordinator()
        // Note: NotificationCoordinator.configure() is called in ContentView after AIFeaturesCoordinator is available
        _firestoreCoordinator = State(wrappedValue: firestore)
        _authService = State(wrappedValue: AuthCoordinator())
        _messagingCoordinator = State(wrappedValue: MessagingCoordinator())
        _notificationService = State(wrappedValue: notification)
        _networkMonitor = State(wrappedValue: NetworkMonitor())
        _aiCoordinator = State(wrappedValue: AIFeaturesCoordinator())
        _typingStatusService = State(wrappedValue: TypingStatusService())
        _networkSimulator = State(wrappedValue: NetworkSimulator())
        appDelegate.notificationService = notification
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(firestoreCoordinator)
                .environment(messagingCoordinator)
                .environment(notificationService)
                .environment(networkMonitor)
                .environment(aiCoordinator)
                .environment(typingStatusService)
                .environment(networkSimulator)
        }
        .modelContainer(sharedModelContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    var notificationService: NotificationCoordinator?

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
