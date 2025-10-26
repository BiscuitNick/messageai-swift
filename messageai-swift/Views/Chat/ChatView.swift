//
//  ChatView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let conversation: ConversationEntity
    let currentUser: AuthCoordinator.AppUser
    private let conversationId: String
    private let participantIds: [String]
    private let scrollToMessageId: String?

    @Environment(MessagingCoordinator.self) private var messagingCoordinator
    @Environment(AuthCoordinator.self) private var authService
    @Environment(NotificationCoordinator.self) private var notificationService
    @Environment(FirestoreCoordinator.self) private var firestoreCoordinator
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(AIFeaturesCoordinator.self) private var aiCoordinator
    @Environment(TypingStatusService.self) private var typingStatusService
    @Environment(\.modelContext) private var modelContext

    @State private var messageText: String = ""
    @State private var sendError: String?
    @State private var isSending: Bool = false
    @State private var isBotTyping: Bool = false
    @State private var showingSummary: Bool = false
    @State private var selectedTab: ChatTab = .messages
    @State private var hasScrolledToMessage = false
    @State private var showMeetingSuggestions: Bool = false
    @State private var meetingSuggestions: MeetingSuggestionsResponse?
    @State private var showSchedulingBanner: Bool = false
    @State private var activeTypers: [TypingStatusService.TypingIndicator] = []
    @FocusState private var composerFocused: Bool

    private var isAIConversation: Bool {
        conversation.participantIds.contains { $0.hasPrefix("bot:") }
    }

    private var activeBot: BotEntity? {
        guard let botParticipantId = conversation.participantIds.first(where: { $0.hasPrefix("bot:") }) else {
            return nil
        }
        let botId = String(botParticipantId.dropFirst(4)) // Remove "bot:" prefix
        return botLookup[botId]
    }

    @Query private var participants: [UserEntity]
    @Query private var bots: [BotEntity]
    @Query private var messages: [MessageEntity]

    private var participantLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
    }

    private var botLookup: [String: BotEntity] {
        Dictionary(uniqueKeysWithValues: bots.map { ($0.id, $0) })
    }

    private var groupedMessages: [(date: Date, items: [MessageEntity])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return groups.keys.sorted().map { date in
            let items = groups[date]?.sorted(by: { $0.timestamp < $1.timestamp }) ?? []
            return (date: date, items: items)
        }
    }

    init(conversation: ConversationEntity, currentUser: AuthCoordinator.AppUser, scrollToMessageId: String? = nil) {
        let conversationId = conversation.id
        let participantIds = conversation.participantIds

        self.conversation = conversation
        self.currentUser = currentUser
        self.conversationId = conversationId
        self.participantIds = participantIds
        self.scrollToMessageId = scrollToMessageId
        _participants = Query(
            filter: #Predicate<UserEntity> { user in
                participantIds.contains(user.id)
            }
        )
        _messages = Query(
            filter: #Predicate<MessageEntity> { message in
                message.conversationId == conversationId
            },
            sort: [SortDescriptor(\MessageEntity.timestamp, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                ForEach(ChatTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content
            switch selectedTab {
            case .messages:
                messagesTab
            case .actionItems:
                ActionItemsTabView(conversationId: conversationId)
            case .decisions:
                DecisionsTabView(conversationId: conversationId)
            }
        }
        .navigationTitle(chatTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Meeting Suggestions button (only for non-AI conversations with multiple participants)
                    if !isAIConversation && conversation.participantIds.count >= 2 {
                        Button(action: { loadMeetingSuggestions() }) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.primary)
                        }
                    }

                    // Thread Summary button
                    Button(action: { showingSummary = true }) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear {
            notificationService.setActiveConversation(conversationId)
            // Start Firestore listeners for AI features
            firestoreCoordinator.startActionItemsListener(conversationId: conversationId, modelContext: modelContext)
            firestoreCoordinator.startDecisionsListener(conversationId: conversationId, modelContext: modelContext)
        }
        .onDisappear {
            notificationService.setActiveConversation(nil)
            // Stop Firestore listeners to prevent memory leaks
            firestoreCoordinator.stopActionItemsListener(conversationId: conversationId)
            firestoreCoordinator.stopDecisionsListener(conversationId: conversationId)
        }
        .sheet(isPresented: $showingSummary) {
            NavigationStack {
                ScrollView {
                    ThreadSummaryCard(
                        summary: aiCoordinator.summaryService.fetchThreadSummary(for: conversationId).map { entity in
                            ThreadSummaryResponse(
                                summary: entity.summary,
                                keyPoints: entity.keyPoints,
                                conversationId: entity.conversationId,
                                timestamp: entity.generatedAt,
                                messageCount: entity.messageCount
                            )
                        },
                        isLoading: aiCoordinator.summaryService.state.isLoading(conversationId),
                        error: aiCoordinator.summaryService.state.error(for: conversationId),
                        onRefresh: {
                            Task {
                                do {
                                    _ = try await aiCoordinator.summaryService.summarizeThread(
                                        conversationId: conversationId,
                                        forceRefresh: true
                                    )
                                } catch {
                                    print("Failed to refresh summary: \(error)")
                                }
                            }
                        }
                    )
                    .padding()
                }
                .navigationTitle("Thread Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingSummary = false
                        }
                    }
                }
            }
        }
        .onAppear {
            notificationService.setActiveConversation(conversationId)
            // Start Firestore listeners for AI features
            firestoreCoordinator.startActionItemsListener(conversationId: conversationId, modelContext: modelContext)
            firestoreCoordinator.startDecisionsListener(conversationId: conversationId, modelContext: modelContext)
        }
        .onDisappear {
            notificationService.setActiveConversation(nil)
            // Stop Firestore listeners to prevent memory leaks
            firestoreCoordinator.stopActionItemsListener(conversationId: conversationId)
            firestoreCoordinator.stopDecisionsListener(conversationId: conversationId)
            typingStatusService.stopObserving(conversationId: conversationId)
        }
        .task {
            // Observe typing status
            typingStatusService.observeTypingStatus(conversationId: conversationId) { indicators in
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeTypers = indicators
                }
            }
        }
        .onChange(of: messageText) { oldValue, newValue in
            // Send typing notification when user starts typing
            let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if oldTrimmed.isEmpty && !newTrimmed.isEmpty {
                // User started typing
                Task {
                    try? await typingStatusService.setTyping(conversationId: conversationId, isTyping: true)
                }
            } else if !oldTrimmed.isEmpty && newTrimmed.isEmpty {
                // User cleared text
                Task {
                    try? await typingStatusService.setTyping(conversationId: conversationId, isTyping: false)
                }
            }
        }
        .alert(
            "Unable to send message",
            isPresented: .init(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { sendError = nil }
            },
            message: {
                Text(sendError ?? "Unknown error")
            }
        )
    }

    private var messagesTab: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedMessages, id: \.date) { group in
                            Section {
                                ForEach(group.items) { message in
                                    MessageBubble(
                                        message: message,
                                        isCurrentUser: message.senderId == currentUser.id,
                                        currentUserId: currentUser.id,
                                        conversation: conversation,
                                        sender: senderForMessage(message),
                                        bot: botForMessage(message),
                                        participants: participants,
                                        isOnline: networkMonitor.isConnected,
                                        onRetryMessage: {
                                            Task {
                                                try? await messagingCoordinator.retryFailedMessage(messageId: message.id)
                                            }
                                        }
                                    )
                                    .id(message.id)
                                }
                            } header: {
                                DateHeader(date: group.date)
                                    .padding(.vertical, 4)
                            }
                        }

                        if isBotTyping {
                            TypingIndicator(bot: activeBot, isOnline: networkMonitor.isConnected)
                                .id("typing-indicator")
                        }

                        Spacer().frame(height: 8)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .background(Color(.systemGroupedBackground))
                .onTapGesture {
                    // Track user interaction on tap
                    Task {
                        await messagingCoordinator.markConversationAsRead(conversationId)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5).onChanged { _ in
                        // Track user interaction on scroll
                        Task {
                            await messagingCoordinator.markConversationAsRead(conversationId)
                        }
                    }
                )
                .onChange(of: messages.count) { oldCount, newCount in
                    withAnimation(.easeOut(duration: 0.25)) {
                        scrollToBottom(proxy: proxy)
                    }

                    // Turn off typing indicator when bot message arrives
                    if isAIConversation && isBotTyping && newCount > oldCount {
                        if let lastMessage = messages.last, lastMessage.senderId.hasPrefix("bot:") {
                            isBotTyping = false
                        }
                    }

                    Task {
                        await messagingCoordinator.markConversationAsRead(conversationId)
                    }
                }
                .onChange(of: isBotTyping) { _, isTyping in
                    if isTyping {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                .onChange(of: aiCoordinator.schedulingService.intentDetected[conversationId]) { _, detected in
                    // Auto-show banner when scheduling intent is detected
                    if detected == true && !aiCoordinator.schedulingService.isSchedulingSuggestionsSnoozed(for: conversationId) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSchedulingBanner = true
                        }
                    }
                }
                .task {
                    #if DEBUG
                    print("[ChatView] Starting message listener for conversation: \(conversationId)")
                    #endif
                    messagingCoordinator.ensureMessageListener(for: conversationId)
                    await messagingCoordinator.markConversationAsRead(conversationId)

                    // Scroll to specific message if provided (from search), otherwise scroll to bottom
                    if let messageId = scrollToMessageId, !hasScrolledToMessage {
                        // Give a moment for messages to load
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        withAnimation {
                            proxy.scrollTo(messageId, anchor: .center)
                        }
                        hasScrolledToMessage = true
                    } else {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            // Scheduling Intent Banner
            if showSchedulingBanner && !aiCoordinator.schedulingService.isSchedulingSuggestionsSnoozed(for: conversationId) {
                SchedulingIntentBanner(
                    confidence: aiCoordinator.schedulingService.intentConfidence[conversationId] ?? 0.0,
                    onViewSuggestions: {
                        withAnimation {
                            showSchedulingBanner = false
                            showMeetingSuggestions = true
                            loadMeetingSuggestions(forceRefresh: false)
                        }
                    },
                    onSnooze: {
                        do {
                            try aiCoordinator.schedulingService.snoozeSuggestions(for: conversationId)
                            withAnimation {
                                showSchedulingBanner = false
                            }
                        } catch {
                            print("[ChatView] Failed to snooze: \(error)")
                        }
                    },
                    onDismiss: {
                        withAnimation {
                            showSchedulingBanner = false
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }

            // Meeting Suggestions Panel
            if showMeetingSuggestions {
                MeetingSuggestionsPanel(
                    suggestions: meetingSuggestions,
                    isLoading: aiCoordinator.meetingSuggestionsService.state.isLoading(conversationId),
                    error: aiCoordinator.meetingSuggestionsService.state.error(for: conversationId),
                    onRefresh: { loadMeetingSuggestions(forceRefresh: true) },
                    onCopy: { suggestion in
                        copyMeetingSuggestion(suggestion)
                    },
                    onShare: { suggestion in
                        shareMeetingSuggestion(suggestion)
                    },
                    onAddToCalendar: { suggestion in
                        addToCalendar(suggestion)
                    },
                    onDismiss: {
                        withAnimation {
                            showMeetingSuggestions = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Typing Indicators
            if !activeTypers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeTypers) { typer in
                        TypingBubble(
                            user: participantLookup[typer.userId],
                            displayName: participantLookup[typer.userId]?.displayName ?? typer.displayName,
                            isGroupChat: conversation.isGroup,
                            isOnline: networkMonitor.isConnected
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()

            ComposerView(
                messageText: $messageText,
                isSending: isSending,
                sendAction: sendMessage
            )
            .focused($composerFocused)
        }
    }

    private var chatTitle: String {
        if conversation.isGroup {
            return conversation.groupName ?? "Group Chat"
        }
        let others = participantIds.filter { $0 != currentUser.id }
        if let first = others.first {
            // Check if it's a bot
            if first.hasPrefix("bot:") {
                if let bot = bots.first(where: { "bot:\($0.id)" == first }) {
                    return "\(bot.name) ✨"
                }
            } else if let user = participants.first(where: { $0.id == first }) {
                return user.displayName
            }
        }
        return "Conversation"
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let content = text

        // Capture message data synchronously on MainActor BEFORE the Task
        // This avoids a deadlock where we try to read from SwiftData while
        // the Firestore listener is trying to write to it
        let currentMessages = messages.map { message in
            (senderId: message.senderId, text: message.text)
        }

        Task {
            isSending = true
            defer { isSending = false }
            do {
                // Send user's message
                try await messagingCoordinator.sendMessage(conversationId: conversationId, text: content)
                messageText = ""

                // Clear typing status
                try? await typingStatusService.setTyping(conversationId: conversationId, isTyping: false)

                // If this is an AI conversation, call the agent
                // The agent will write its response directly to Firestore
                if isAIConversation {
                    // Show typing indicator
                    isBotTyping = true

                    do {
                        // Build conversation history from captured data
                        let conversationHistory = currentMessages.map { msg in
                            BotAgentService.AgentMessage(
                                role: msg.senderId == currentUser.id ? "user" : "assistant",
                                content: msg.text
                            )
                        }

                        // Add the current message to history
                        let fullHistory = conversationHistory + [
                            BotAgentService.AgentMessage(
                                role: "user",
                                content: content
                            )
                        ]

                        try await firestoreCoordinator.chatWithAgent(
                            messages: fullHistory,
                            conversationId: conversationId
                        )
                    } catch {
                        // If AI fails, hide typing indicator and log the error
                        isBotTyping = false
                        print("AI error: \(error.localizedDescription)")
                    }
                }
            } catch {
                sendError = error.localizedDescription
            }
            if !composerFocused {
                composerFocused = true
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isBotTyping {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
        } else if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func senderForMessage(_ message: MessageEntity) -> UserEntity? {
        if message.senderId.hasPrefix("bot:") {
            return nil
        }
        return participantLookup[message.senderId]
    }

    private func botForMessage(_ message: MessageEntity) -> BotEntity? {
        if message.senderId.hasPrefix("bot:") {
            let botId = String(message.senderId.dropFirst(4)) // Remove "bot:" prefix
            return botLookup[botId]
        }
        return nil
    }

    // MARK: - Meeting Suggestions

    private func loadMeetingSuggestions(forceRefresh: Bool = false) {
        withAnimation {
            showMeetingSuggestions = true
        }

        Task {
            do {
                let response = try await aiCoordinator.meetingSuggestionsService.suggestMeetingTimes(
                    conversationId: conversationId,
                    participantIds: participantIds.filter { !$0.hasPrefix("bot:") },
                    durationMinutes: 60, // Default 1 hour
                    preferredDays: 14,
                    forceRefresh: forceRefresh
                )
                await MainActor.run {
                    meetingSuggestions = response
                }
            } catch {
                print("Failed to load meeting suggestions: \(error.localizedDescription)")
            }
        }
    }

    private func copyMeetingSuggestion(_ suggestion: MeetingTimeSuggestion) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let text = """
        Meeting Time Suggestion:
        When: \(formatter.string(from: suggestion.startTime)) - \(formatter.string(from: suggestion.endTime))
        Day: \(suggestion.dayOfWeek), \(suggestion.timeOfDay.displayLabel)
        Reason: \(suggestion.justification)
        """

        #if os(iOS)
        UIPasteboard.general.string = text
        #endif

        // Track analytics
        Task {
            await aiCoordinator.meetingSuggestionsService.trackInteraction(
                conversationId: conversationId,
                action: "copy",
                suggestionIndex: meetingSuggestions?.suggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0,
                suggestionScore: suggestion.score
            )
        }
    }

    private func shareMeetingSuggestion(_ suggestion: MeetingTimeSuggestion) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let text = """
        Meeting Time Suggestion:
        When: \(formatter.string(from: suggestion.startTime)) - \(formatter.string(from: suggestion.endTime))
        Day: \(suggestion.dayOfWeek), \(suggestion.timeOfDay.displayLabel)
        Reason: \(suggestion.justification)
        """

        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // Find the topmost view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(activityVC, animated: true)
        }
        #endif

        // Track analytics
        Task {
            await aiCoordinator.meetingSuggestionsService.trackInteraction(
                conversationId: conversationId,
                action: "share",
                suggestionIndex: meetingSuggestions?.suggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0,
                suggestionScore: suggestion.score
            )
        }
    }

    private func addToCalendar(_ suggestion: MeetingTimeSuggestion) {
        // Create calendar deep link URL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let startTime = dateFormatter.string(from: suggestion.startTime)
        let endTime = dateFormatter.string(from: suggestion.endTime)

        // Format title and details
        let title = "Meeting"
        let details = suggestion.justification.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Create Google Calendar URL (most universal option)
        let googleCalendarURL = "https://calendar.google.com/calendar/render?action=TEMPLATE&text=\(title)&dates=\(startTime)/\(endTime)&details=\(details)"

        // Create Apple Calendar data URL as alternative
        let appleCalendarData = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        DTSTART:\(startTime)
        DTEND:\(endTime)
        SUMMARY:\(title)
        DESCRIPTION:\(suggestion.justification)
        END:VEVENT
        END:VCALENDAR
        """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Try to open the calendar URL
        #if os(iOS)
        if let url = URL(string: googleCalendarURL) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    print("Failed to open calendar URL")
                }
            }
        }
        #endif

        // Track analytics
        Task {
            await aiCoordinator.meetingSuggestionsService.trackInteraction(
                conversationId: conversationId,
                action: "add_to_calendar",
                suggestionIndex: meetingSuggestions?.suggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0,
                suggestionScore: suggestion.score
            )
        }
    }
}

