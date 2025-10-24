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

    @Environment(AuthService.self) private var authService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(MessagingService.self) private var messagingService
    @Environment(NotificationService.self) private var notificationService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(AIFeaturesService.self) private var aiFeaturesService
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
            authService.configure(modelContext: modelContext, firestoreService: firestoreService)
            aiFeaturesService.configure(
                modelContext: modelContext,
                authService: authService,
                messagingService: messagingService,
                firestoreService: firestoreService,
                networkMonitor: networkMonitor
            )
            notificationService.configure(aiFeaturesService: aiFeaturesService)
            firestoreService.startUserListener(modelContext: modelContext)
            firestoreService.startBotListener(modelContext: modelContext)
            hasStartedUserListener = true
            hasStartedBotListener = true
            await notificationService.requestAuthorization()
            await notificationService.registerForRemoteNotifications()
            // Ensure bot exists in Firestore
            do {
                try await firestoreService.ensureBotExists()
                print("✅ Bot initialization complete")
            } catch {
                print("❌ Failed to ensure bot exists: \(error.localizedDescription)")
            }
            if let userId = authService.currentUser?.id {
                messagingService.configure(modelContext: modelContext, currentUserId: userId, notificationService: notificationService)
                // Wire AI Features message observer
                messagingService.onMessageMutation = { [weak aiFeaturesService] conversationId, messageId in
                    aiFeaturesService?.onMessageMutation(conversationId: conversationId, messageId: messageId)
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
                        firestoreService.stopUserListener()
                        hasStartedUserListener = false
                    }
                    if hasStartedBotListener {
                        firestoreService.stopBotListener()
                        hasStartedBotListener = false
                    }
                    messagingService.reset()
                    aiFeaturesService.onSignOut()
                    authService.sceneDidEnterBackground()
                    selectedTab = .chats
                    return
                }
                if !hasStartedUserListener {
                    firestoreService.startUserListener(modelContext: modelContext)
                    hasStartedUserListener = true
                }
                if !hasStartedBotListener {
                    firestoreService.startBotListener(modelContext: modelContext)
                    hasStartedBotListener = true
                }
                await notificationService.registerForRemoteNotifications()
                messagingService.configure(modelContext: modelContext, currentUserId: newId, notificationService: notificationService)
                // Wire AI Features message observer
                messagingService.onMessageMutation = { [weak aiFeaturesService] conversationId, messageId in
                    aiFeaturesService?.onMessageMutation(conversationId: conversationId, messageId: messageId)
                }
                aiFeaturesService.onSignIn()
                await authService.markCurrentUserOnline()
                authService.sceneDidBecomeActive()
                selectedTab = .chats
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                switch newPhase {
                case .active:
                    messagingService.setAppInForeground(true)
                    authService.sceneDidBecomeActive()
                    // Refresh coordination insights when app becomes active
                    await aiFeaturesService.refreshCoordinationInsights()
                case .background:
                    messagingService.setAppInForeground(false)
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
                    await aiFeaturesService.processPendingSchedulingSuggestions()
                    await aiFeaturesService.refreshCoordinationInsights()
                }
            }
        }
    }
}
