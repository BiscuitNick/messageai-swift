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
    private enum TabSelection {
        case chats
        case users
        case profile
        case debug
    }

    @Environment(AuthCoordinator.self) private var authService
    @Environment(FirestoreCoordinator.self) private var firestoreCoordinator
    @Environment(MessagingCoordinator.self) private var messagingCoordinator
    @Environment(NotificationCoordinator.self) private var notificationService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(AIFeaturesCoordinator.self) private var aiCoordinator
    @Environment(TypingStatusService.self) private var typingStatusService
    @Environment(NetworkSimulator.self) private var networkSimulator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasConfiguredContext = false
    @State private var hasStartedUserListener = false
    @State private var hasStartedBotListener = false
    @State private var selectedTab: TabSelection = .chats

    var body: some View {
        Group {
            if let user = authService.currentUser {
                TabView(selection: $selectedTab) {
                    ConversationsRootView(currentUser: user)
                        .tabItem {
                            Label("Chats", systemImage: "bubble.left.and.bubble.right")
                        }
                        .tag(TabSelection.chats)

                    UsersDebugView(currentUser: user)
                        .tabItem {
                            Label("Users", systemImage: "person.3")
                        }
                        .tag(TabSelection.users)

                    ProfileTabView(currentUser: user)
                        .tabItem {
                            Label("Profile", systemImage: "person.crop.circle")
                        }
                        .tag(TabSelection.profile)

                    DebugView(currentUser: user)
                        .tabItem {
                            Label("Debug", systemImage: "wrench.and.screwdriver")
                        }
                        .tag(TabSelection.debug)
                }
            } else {
                AuthView()
            }
        }
        .task {
            guard !hasConfiguredContext else { return }
            authService.configure(modelContext: modelContext, firestoreCoordinator: firestoreCoordinator)
            aiCoordinator.configure(
                modelContext: modelContext,
                authService: authService,
                messagingService: messagingCoordinator,
                firestoreCoordinator: firestoreCoordinator,
                networkMonitor: networkMonitor
            )
            notificationService.configure(aiFeaturesService: aiCoordinator)
            firestoreCoordinator.startUserListener(modelContext: modelContext)
            firestoreCoordinator.startBotListener(modelContext: modelContext)
            hasStartedUserListener = true
            hasStartedBotListener = true
            await notificationService.requestAuthorization()
            await notificationService.registerForRemoteNotifications()
            // Ensure bot exists in Firestore
            do {
                try await firestoreCoordinator.ensureBotExists()
                print("✅ Bot initialization complete")
            } catch {
                print("❌ Failed to ensure bot exists: \(error.localizedDescription)")
            }
            if let userId = authService.currentUser?.id {
                messagingCoordinator.configure(modelContext: modelContext, currentUserId: userId, notificationService: notificationService, networkSimulator: networkSimulator)
                typingStatusService.configure(currentUserId: userId)
                // Wire AI Features message observer
                messagingCoordinator.onMessageMutation = { [weak aiCoordinator] conversationId, messageId in
                    aiCoordinator?.onMessageMutation(conversationId: conversationId, messageId: messageId)
                }
            }
            await authService.markCurrentUserOnline()
            authService.sceneDidBecomeActive()
            hasConfiguredContext = true
        }
        .onChange(of: authService.currentUser?.id) { _, newId in
            Task { @MainActor in
                guard let newId else {
                    if hasStartedUserListener {
                        firestoreCoordinator.stopUserListener()
                        hasStartedUserListener = false
                    }
                    if hasStartedBotListener {
                        firestoreCoordinator.stopBotListener()
                        hasStartedBotListener = false
                    }
                    messagingCoordinator.reset()
                    aiCoordinator.onSignOut()
                    authService.sceneDidEnterBackground()
                    selectedTab = .chats
                    return
                }
                if !hasStartedUserListener {
                    firestoreCoordinator.startUserListener(modelContext: modelContext)
                    hasStartedUserListener = true
                }
                if !hasStartedBotListener {
                    firestoreCoordinator.startBotListener(modelContext: modelContext)
                    hasStartedBotListener = true
                }
                await notificationService.registerForRemoteNotifications()
                messagingCoordinator.configure(modelContext: modelContext, currentUserId: newId, notificationService: notificationService, networkSimulator: networkSimulator)
                typingStatusService.configure(currentUserId: newId)
                // Wire AI Features message observer
                messagingCoordinator.onMessageMutation = { [weak aiCoordinator] conversationId, messageId in
                    aiCoordinator?.onMessageMutation(conversationId: conversationId, messageId: messageId)
                }
                aiCoordinator.onSignIn()
                await authService.markCurrentUserOnline()
                authService.sceneDidBecomeActive()
                selectedTab = .chats
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                switch newPhase {
                case .active:
                    messagingCoordinator.setAppInForeground(true)
                    authService.sceneDidBecomeActive()
                    // Refresh coordination insights when app becomes active
                    await aiCoordinator.refreshCoordinationInsights()
                case .background:
                    messagingCoordinator.setAppInForeground(false)
                    authService.sceneDidEnterBackground()
                default:
                    break
                }
            }
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            // When network connectivity returns, process pending work and refresh coordination insights
            if !oldValue && newValue {
                Task { @MainActor in
                    #if DEBUG
                    print("[ContentView] Network connectivity restored - processing pending work")
                    #endif
                    await aiCoordinator.processPendingSchedulingSuggestions()
                    await aiCoordinator.refreshCoordinationInsights()
                }
            }
        }
    }
}
