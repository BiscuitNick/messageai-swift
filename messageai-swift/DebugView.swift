import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI
import SwiftData

struct DebugView: View {
    let currentUser: AuthService.AppUser

    @Environment(AuthService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(MessagingService.self) private var messagingService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(AIFeaturesService.self) private var aiFeaturesService
    private let functions = Functions.functions(region: "us-central1")

    @Query private var bots: [BotEntity]

    @State private var serverTimeResult: String?
    @State private var serverTimeError: String?
    @State private var mockStatus: String?
    @State private var mockError: String?
    @State private var isMockBusy = false
    @State private var deleteConversationsStatus: String?
    @State private var deleteConversationsError: String?
    @State private var isDeletingConversations = false
    @State private var deleteUsersStatus: String?
    @State private var deleteUsersError: String?
    @State private var isDeletingUsers = false
    @State private var recreateBotsStatus: String?
    @State private var recreateBotsError: String?
    @State private var isRecreatingBots = false
    @State private var deleteBotsStatus: String?
    @State private var deleteBotsError: String?
    @State private var isDeletingBots = false

    // Thread Summarization states
    @State private var summarizeStatus: String?
    @State private var summarizeError: String?
    @State private var isSummarizing = false
    @State private var latestSummary: String?

    var body: some View {
        NavigationStack {
            List {
                maintenanceSection
                aiFeaturesSection
                firebaseSection
                authSection
                botsSection
                messagingSection
                notificationSection
                serverTimeSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Test")
        }
    }

    private var aiFeaturesSection: some View {
        Section("AI Features") {
            Button {
                Task { await summarizeNewestConversation() }
            } label: {
                if isSummarizing {
                    ProgressView()
                } else {
                    Label("Summarize Newest Conversation", systemImage: "doc.text.magnifyingglass")
                }
            }
            .disabled(isSummarizing)

            statusText(success: summarizeStatus, error: summarizeError)

            if let summary = latestSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Summary:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }
        }
    }

    private var botsSection: some View {
        Section("AI Bots") {
            LabeledContent("Bots in SwiftData", value: "\(bots.count)")

            if bots.isEmpty {
                Text("No bots found")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(bots) { bot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(bot.name)
                                .font(.headline)
                            Text("✨")
                                .font(.caption)
                        }
                        Text("ID: \(bot.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Category: \(bot.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Active: \(bot.isActive ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundStyle(bot.isActive ? .green : .red)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var firebaseSection: some View {
        Section("Firebase App") {
            if let options = firebaseOptions {
                LabeledContent("Project ID", value: options.projectID ?? "Unavailable")
                LabeledContent("App ID", value: options.googleAppID)
                LabeledContent("API Key", value: options.apiKey ?? "Unavailable")
                LabeledContent("Database URL", value: options.databaseURL ?? "Unavailable")
                LabeledContent("Storage Bucket", value: options.storageBucket ?? "Unavailable")
            } else {
                Text("Firebase not configured.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authSection: some View {
        Section("Authentication") {
            LabeledContent("Current User", value: currentUser.displayName)
            LabeledContent("User ID", value: currentUser.id)
            LabeledContent("Email", value: currentUser.email)
            LabeledContent("Firebase UID", value: Auth.auth().currentUser?.uid ?? "Unavailable")
            LabeledContent("Email Verified", value: Auth.auth().currentUser?.isEmailVerified == true ? "Yes" : "No")
        }
    }

    private var messagingSection: some View {
        Section("Messaging Service") {
            LabeledContent("Configured", value: messagingDebug.isConfigured ? "Yes" : "No")
            LabeledContent("Active User ID", value: messagingDebug.currentUserId ?? "nil")
            LabeledContent("Conversation Listener", value: messagingDebug.conversationListenerActive ? "Active" : "Inactive")
            LabeledContent("Message Listeners", value: "\(messagingDebug.activeMessageListeners)")
            LabeledContent("Pending Message Tasks", value: "\(messagingDebug.pendingMessageTasks)")
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            LabeledContent(
                "Authorization",
                value: statusDescription(for: notificationService.authorizationStatus)
            )
            LabeledContent("FCM Token", value: notificationService.fcmToken ?? "Unavailable")
        }
    }

    private var maintenanceSection: some View {
        Section("Database Tools") {
            Button {
                Task { await recreateBots() }
            } label: {
                if isRecreatingBots {
                    ProgressView()
                } else {
                    Label("Recreate Bots", systemImage: "sparkles")
                }
            }
            .disabled(isRecreatingBots)

            statusText(success: recreateBotsStatus, error: recreateBotsError)

            Button(role: .destructive) {
                Task { await deleteBots() }
            } label: {
                if isDeletingBots {
                    ProgressView()
                } else {
                    Label("Delete Bots", systemImage: "trash")
                }
            }
            .disabled(isDeletingBots)

            statusText(success: deleteBotsStatus, error: deleteBotsError)

            Button {
                Task { await triggerMockSeed() }
            } label: {
                if isMockBusy {
                    ProgressView()
                } else {
                    Label("Seed Mock Data", systemImage: "sparkles")
                }
            }
            .disabled(isMockBusy)

            statusText(success: mockStatus, error: mockError)

            Button(role: .destructive) {
                Task { await deleteConversations() }
            } label: {
                if isDeletingConversations {
                    ProgressView()
                } else {
                    Label("Delete Conversations", systemImage: "trash")
                }
            }
            .disabled(isDeletingConversations)

            statusText(success: deleteConversationsStatus, error: deleteConversationsError)

            Button(role: .destructive) {
                Task { await deleteUsers() }
            } label: {
                if isDeletingUsers {
                    ProgressView()
                } else {
                    Label("Delete Users", systemImage: "person.crop.circle.badge.xmark")
                }
            }
            .disabled(isDeletingUsers)

            statusText(success: deleteUsersStatus, error: deleteUsersError)
        }
    }

    private var serverTimeSection: some View {
        Section("Cloud Functions") {
            Button("Fetch Server Time") {
                Task { await fetchServerTime() }
            }
            if let result = serverTimeResult {
                LabeledContent("Last Result", value: result)
            }
            if let error = serverTimeError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @MainActor
    private func fetchServerTime() async {
        serverTimeResult = nil
        serverTimeError = nil
        do {
            let data = try await functions.httpsCallable("getServerTime").call([String: Any]())
            if let dict = data.data as? [String: Any],
               let iso = dict["iso"] as? String {
                serverTimeResult = iso
            } else {
                serverTimeResult = "Received unexpected payload"
            }
        } catch {
            serverTimeError = describe(error)
        }
    }

    @MainActor
    private func triggerMockSeed() async {
        mockStatus = nil
        mockError = nil
        isMockBusy = true
        defer { isMockBusy = false }
        do {
            try await functions.httpsCallable("generateMockData").call([String: Any]())
            mockStatus = "Mock data seeded at \(Date().formatted(dateTimeFormatter))"
        } catch {
            mockError = describe(error)
        }
    }

    @MainActor
    private func deleteConversations() async {
        deleteConversationsStatus = nil
        deleteConversationsError = nil
        isDeletingConversations = true
        defer { isDeletingConversations = false }
        do {
            try await functions.httpsCallable("deleteConversations").call([String: Any]())
            deleteConversationsStatus = "Conversations cleared at \(Date().formatted(dateTimeFormatter))"
        } catch {
            deleteConversationsError = describe(error)
        }
    }

    @MainActor
    private func deleteUsers() async {
        deleteUsersStatus = nil
        deleteUsersError = nil
        isDeletingUsers = true
        defer { isDeletingUsers = false }
        do {
            try await functions.httpsCallable("deleteUsers").call([String: Any]())
            deleteUsersStatus = "Users cleared at \(Date().formatted(dateTimeFormatter))"
        } catch {
            deleteUsersError = describe(error)
        }
    }

    @MainActor
    private func recreateBots() async {
        recreateBotsStatus = nil
        recreateBotsError = nil
        isRecreatingBots = true
        defer { isRecreatingBots = false }
        do {
            try await firestoreService.ensureBotExists()
            recreateBotsStatus = "Bots recreated at \(Date().formatted(dateTimeFormatter))"
        } catch {
            recreateBotsError = describe(error)
        }
    }

    @MainActor
    private func deleteBots() async {
        deleteBotsStatus = nil
        deleteBotsError = nil
        isDeletingBots = true
        defer { isDeletingBots = false }
        do {
            try await firestoreService.deleteBots()
            deleteBotsStatus = "Bots deleted at \(Date().formatted(dateTimeFormatter))"
        } catch {
            deleteBotsError = describe(error)
        }
    }

    @MainActor
    private func summarizeNewestConversation() async {
        summarizeStatus = nil
        summarizeError = nil
        latestSummary = nil
        isSummarizing = true
        defer { isSummarizing = false }

        do {
            let response = try await aiFeaturesService.summarizeThread(saveToDB: false)

            latestSummary = response.summary
            summarizeStatus = "Summarized \(response.messageCount) messages from conversation"
            print("Summary generated: \(response.summary)")
        } catch {
            summarizeError = "Error: \(describe(error))"
            print("Summarization error details: \(error)")
        }
    }

    private func statusText(success: String?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let success {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var firebaseOptions: FirebaseOptions? {
        FirebaseApp.app()?.options
    }

    private var messagingDebug: MessagingService.DebugSnapshot {
        messagingService.debugSnapshot
    }

    private func statusDescription(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    private var dateTimeFormatter: Date.FormatStyle {
        .dateTime.year().month().day().hour().minute()
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .unauthenticated:
                return "Authentication required. Sign in again."
            case .permissionDenied:
                return "Permission denied."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
