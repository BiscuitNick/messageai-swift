//
//  ChatView.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/21/25.
//

import SwiftUI
import SwiftData

enum ChatTab: String, CaseIterable {
    case messages = "Messages"
    case actionItems = "Action Items"
    case decisions = "Decisions"
}

struct ChatView: View {
    let conversation: ConversationEntity
    let currentUser: AuthService.AppUser
    private let conversationId: String
    private let participantIds: [String]
    private let scrollToMessageId: String?

    @Environment(MessagingService.self) private var messagingService
    @Environment(AuthService.self) private var authService
    @Environment(NotificationService.self) private var notificationService
    @Environment(FirestoreService.self) private var firestoreService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(AIFeaturesService.self) private var aiFeaturesService
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

    init(conversation: ConversationEntity, currentUser: AuthService.AppUser, scrollToMessageId: String? = nil) {
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
            firestoreService.startActionItemsListener(conversationId: conversationId, modelContext: modelContext)
            firestoreService.startDecisionsListener(conversationId: conversationId, modelContext: modelContext)
        }
        .onDisappear {
            notificationService.setActiveConversation(nil)
            // Stop Firestore listeners to prevent memory leaks
            firestoreService.stopActionItemsListener(conversationId: conversationId)
            firestoreService.stopDecisionsListener(conversationId: conversationId)
        }
        .sheet(isPresented: $showingSummary) {
            NavigationStack {
                ScrollView {
                    ThreadSummaryCard(
                        summary: aiFeaturesService.fetchThreadSummary(for: conversationId).map { entity in
                            ThreadSummaryResponse(
                                summary: entity.summary,
                                keyPoints: entity.keyPoints,
                                conversationId: entity.conversationId,
                                timestamp: entity.generatedAt,
                                messageCount: entity.messageCount
                            )
                        },
                        isLoading: aiFeaturesService.summaryLoadingStates[conversationId] ?? false,
                        error: aiFeaturesService.summaryErrors[conversationId],
                        onRefresh: {
                            Task {
                                do {
                                    _ = try await aiFeaturesService.summarizeThreadTask(
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
            firestoreService.startActionItemsListener(conversationId: conversationId, modelContext: modelContext)
            firestoreService.startDecisionsListener(conversationId: conversationId, modelContext: modelContext)
        }
        .onDisappear {
            notificationService.setActiveConversation(nil)
            // Stop Firestore listeners to prevent memory leaks
            firestoreService.stopActionItemsListener(conversationId: conversationId)
            firestoreService.stopDecisionsListener(conversationId: conversationId)
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
                                                try? await messagingService.retryFailedMessage(messageId: message.id)
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
                        await messagingService.markConversationAsRead(conversationId)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5).onChanged { _ in
                        // Track user interaction on scroll
                        Task {
                            await messagingService.markConversationAsRead(conversationId)
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
                        await messagingService.markConversationAsRead(conversationId)
                    }
                }
                .onChange(of: isBotTyping) { _, isTyping in
                    if isTyping {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                .onChange(of: aiFeaturesService.schedulingIntentDetected[conversationId]) { _, detected in
                    // Auto-show banner when scheduling intent is detected
                    if detected == true && !aiFeaturesService.isSchedulingSuggestionsSnoozed(for: conversationId) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSchedulingBanner = true
                        }
                    }
                }
                .task {
                    messagingService.ensureMessageListener(for: conversationId)
                    await messagingService.markConversationAsRead(conversationId)

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
            if showSchedulingBanner && !aiFeaturesService.isSchedulingSuggestionsSnoozed(for: conversationId) {
                SchedulingIntentBanner(
                    confidence: aiFeaturesService.schedulingIntentConfidence[conversationId] ?? 0.0,
                    onViewSuggestions: {
                        withAnimation {
                            showSchedulingBanner = false
                            showMeetingSuggestions = true
                            loadMeetingSuggestions(forceRefresh: false)
                        }
                    },
                    onSnooze: {
                        do {
                            try aiFeaturesService.snoozeSchedulingSuggestions(for: conversationId)
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
                    isLoading: aiFeaturesService.meetingSuggestionsLoadingStates[conversationId] ?? false,
                    error: aiFeaturesService.meetingSuggestionsErrors[conversationId],
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
                            displayName: participantLookup[typer.userId]?.displayName ?? typer.displayName,
                            isGroupChat: conversation.isGroup
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
                try await messagingService.sendMessage(conversationId: conversationId, text: content)
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
                            FirestoreService.AgentMessage(
                                role: msg.senderId == currentUser.id ? "user" : "assistant",
                                content: msg.text
                            )
                        }

                        // Add the current message to history
                        let fullHistory = conversationHistory + [
                            FirestoreService.AgentMessage(
                                role: "user",
                                content: content
                            )
                        ]

                        try await firestoreService.chatWithAgent(
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
                let response = try await aiFeaturesService.suggestMeetingTimes(
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
            await aiFeaturesService.trackMeetingSuggestionInteraction(
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
            await aiFeaturesService.trackMeetingSuggestionInteraction(
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
            await aiFeaturesService.trackMeetingSuggestionInteraction(
                conversationId: conversationId,
                action: "add_to_calendar",
                suggestionIndex: meetingSuggestions?.suggestions.firstIndex(where: { $0.id == suggestion.id }) ?? 0,
                suggestionScore: suggestion.score
            )
        }
    }
}

private struct MessageBubble: View {
    let message: MessageEntity
    let isCurrentUser: Bool
    let currentUserId: String
    let conversation: ConversationEntity
    let sender: UserEntity?
    let bot: BotEntity?
    let participants: [UserEntity]
    let isOnline: Bool
    let onRetryMessage: (() -> Void)?
    @State private var showingReceiptDetails = false

    private var displayName: String {
        if let bot {
            return bot.name
        }
        return sender?.displayName ?? "Unknown"
    }

    private var avatarURL: String? {
        if let bot {
            return bot.avatarURL
        }
        return sender?.profilePictureURL
    }

    private var presenceStatus: PresenceStatus {
        sender?.presenceStatus ?? .offline
    }

    private static let palette: [Color] = [
        Color(red: 0.17, green: 0.33, blue: 0.82),  // Blue
        Color(red: 0.12, green: 0.55, blue: 0.35),  // Green
        Color(red: 0.56, green: 0.17, blue: 0.68),  // Purple
        Color(red: 0.78, green: 0.20, blue: 0.20),  // Red
        Color(red: 0.94, green: 0.49, blue: 0.12),  // Orange
        Color(red: 0.95, green: 0.55, blue: 0.65),  // Pink
        Color(red: 0.20, green: 0.60, blue: 0.86),  // Light Blue
        Color(red: 0.45, green: 0.55, blue: 0.20)   // Olive
    ]

    private var participantLookup: [String: UserEntity] {
        Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
    }

    private var bubbleColor: Color {
        guard !isCurrentUser else { return Color.accentColor }
        let identifier = sender?.id ?? message.senderId
        return getConsistentColorForUser(identifier)
    }

    private var textColor: Color { Color.white }

    private var metaTextColor: Color {
        Color(.secondaryLabel)
    }

    private var timestampColor: Color {
        Color(.label)
    }

    private var timestampText: String {
        message.timestamp.formatted(date: .omitted, time: .shortened)
    }

    // All unique participant IDs sorted alphabetically (for consistent color assignment)
    // Sort by USER ID ONLY - not display name - for truly stable colors
    private var sortedAllParticipantIds: [String] {
        // Use only the stable participant list from the conversation
        let allIds = Set(conversation.participantIds)

        // Sort by USER ID directly - this NEVER changes
        return allIds.sorted { lhs, rhs in
            if lhs == currentUserId { return true }
            if rhs == currentUserId { return false }
            // Sort by actual ID string, not display name
            return lhs < rhs
        }
    }

    // For display order in checkmarks (sender first, then current user, then others)
    // This can include all participants including those in lastInteractionByUser
    private var orderedParticipantIds: [String] {
        var allIds = Set<String>()
        allIds.formUnion(conversation.participantIds)
        allIds.insert(message.senderId)
        allIds.insert(currentUserId)
        allIds.formUnion(conversation.lastInteractionByUser.keys)

        return allIds.sorted { lhs, rhs in
            if lhs == message.senderId { return true }
            if rhs == message.senderId { return false }
            if lhs == currentUserId { return true }
            if rhs == currentUserId { return false }
            // Sort by ID for stable ordering (display can use names separately)
            return lhs < rhs
        }
    }

    private func getConsistentColorForUser(_ userId: String) -> Color {
        if userId == currentUserId {
            return Color.accentColor
        }
        // Find position in sorted list (excluding current user for color assignment)
        let nonCurrentUserIds = sortedAllParticipantIds.filter { $0 != currentUserId }
        if let position = nonCurrentUserIds.firstIndex(of: userId) {
            let index = position % MessageBubble.palette.count
            return MessageBubble.palette[index]
        }
        // Fallback (shouldn't happen)
        return MessageBubble.palette[0]
    }

    private func hasSeen(_ userId: String) -> Bool {
        let userInteraction = conversation.lastInteractionByUser[userId] ?? .distantPast
        let messageTime = message.timestamp
        // Use >= to include exact matches (sender's own messages)
        return userInteraction >= messageTime
    }

    private var otherRecipientIds: [String] {
        orderedParticipantIds.filter { $0 != currentUserId && $0 != message.senderId }
    }

    private var seenRecipientCount: Int {
        otherRecipientIds.filter { hasSeen($0) }.count
    }

    private var totalRecipientCount: Int {
        otherRecipientIds.count
    }

    private var receiptEntries: [ReadStatusEntry] {
        orderedParticipantIds.map { userId in
            let user = participantLookup[userId]
            let isSender = userId == message.senderId
            let isSelf = userId == currentUserId

            let isComplete: Bool
            let statusText: String

            if isSender {
                // For the sender themselves viewing their own message
                if isSelf {
                    // Show complete only when message has hit server
                    isComplete = message.deliveryState != .pending
                    statusText = message.deliveryState == .pending ? "Sending" : "Sent"
                } else {
                    // For recipients viewing the sender's checkmark - always complete
                    // (they wouldn't see the message if it wasn't sent)
                    isComplete = true
                    statusText = "Sent"
                }
            } else {
                // For non-senders, check their interaction timestamp
                isComplete = hasSeen(userId)
                statusText = isComplete ? "Seen" : "Waiting"
            }

            let displayName: String
            if isSelf {
                displayName = "You"
            } else if let user {
                displayName = user.displayName
            } else {
                displayName = userId
            }

            return ReadStatusEntry(
                id: userId,
                displayName: displayName,
                initials: initials(for: userId),
                isSender: isSender,
                isSelf: isSelf,
                isComplete: isComplete,
                statusText: statusText,
                color: participantColor(for: userId, isSender: isSender, isSelf: isSelf)
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 40) }

            if !isCurrentUser {
                if let bot {
                    AvatarView(
                        bot: bot,
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                } else if let sender {
                    AvatarView(
                        user: sender,
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                } else {
                    AvatarView(
                        entity: .custom(initials: senderInitials, profileURL: avatarURL),
                        size: 32,
                        showPresenceIndicator: true,
                        isOnline: isOnline
                    )
                }
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                metadataRow
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)

            if isCurrentUser {
                Spacer(minLength: 8)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, isCurrentUser ? 0 : 4)
        .transition(.move(edge: isCurrentUser ? .trailing : .leading).combined(with: .opacity))
    }

    private var senderInitials: String {
        return initials(from: displayName)
    }

    private var bubbleContent: some View {
        Text(message.text)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if message.hasPriorityData && message.priority.sortOrder >= PriorityLevel.high.sortOrder {
                    Text(message.priority.emoji)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
    }

    private var metadataRow: some View {
        Button(action: { showingReceiptDetails.toggle() }) {
            HStack(spacing: 6) {
                Text(timestampText)
                    .foregroundStyle(timestampColor)
                    .font(.caption2)

                // Show delivery state indicator for sender's own messages
                if message.senderId == currentUserId {
                    DeliveryStateIcon(
                        state: message.deliveryState,
                        onRetry: message.deliveryState == .failed ? onRetryMessage : nil,
                        color: metaTextColor
                    )
                }

                ForEach(receiptEntries) { entry in
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(entry.color)
                        .opacity(entry.isComplete ? 1 : 0.2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingReceiptDetails, attachmentAnchor: .rect(.bounds), arrowEdge: isCurrentUser ? .trailing : .leading) {
            ReadStatusPopover(
                entries: receiptEntries
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func initials(for userId: String) -> String {
        if let user = participantLookup[userId] {
            return initials(from: user.displayName)
        }

        if userId == currentUserId {
            return "ME"
        }

        let cleaned = userId.replacingOccurrences(of: "-", with: " ")
        let fromId = initials(from: cleaned)
        if !fromId.isEmpty {
            return fromId
        }

        let fallback = String(userId.prefix(2)).uppercased()
        return fallback.isEmpty ? "?" : fallback
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map(String.init)
        let combined = initials.prefix(2).joined()
        return combined.isEmpty ? "?" : combined
    }

    private func participantColor(for participantId: String, isSender: Bool, isSelf: Bool) -> Color {
        // Use the same consistent color assignment for all participants
        return getConsistentColorForUser(participantId)
    }
}

private struct DeliveryStateIcon: View {
    let state: MessageDeliveryState
    let onRetry: (() -> Void)?
    var color: Color

    var body: some View {
        switch state {
        case .pending:
            // Animated gray checkmark
            Image(systemName: "checkmark")
                .foregroundStyle(.gray)
                .opacity(0.6)
                .symbolEffect(.pulse)
        case .sent:
            // Single blue checkmark
            Image(systemName: "checkmark")
                .foregroundStyle(.blue)
        case .delivered:
            // Double blue checkmark (regular weight)
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        case .read:
            // Double blue checkmark (bold)
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.bold)
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.bold)
            }
        case .failed:
            // Red exclamation with retry
            if let onRetry {
                Button(action: onRetry) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sending message")
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// Legacy support
private struct DeliveryStatusIcon: View {
    let status: DeliveryStatus
    var color: Color

    var body: some View {
        DeliveryStateIcon(
            state: status.toDeliveryState,
            onRetry: nil,
            color: color
        )
    }
}

private struct ReadStatusEntry: Identifiable {
    let id: String
    let displayName: String
    let initials: String
    let isSender: Bool
    let isSelf: Bool
    let isComplete: Bool
    let statusText: String
    let color: Color
}

private struct ReadStatusPopover: View {
    let entries: [ReadStatusEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.count > 1 {
                Text("Read Receipts")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(entry.color)
                            .opacity(entry.isComplete ? 1 : 0.2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.footnote.weight(.semibold))
                            Text(entry.statusText)
                                .font(.caption2)
                                .foregroundStyle(entry.isComplete ? .secondary : Color.secondary.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DateHeader: View {
    let date: Date
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        Text(formatter.string(from: date))
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

private struct TypingIndicator: View {
    let bot: BotEntity?
    let isOnline: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let bot {
                AvatarView(
                    bot: bot,
                    size: 32,
                    showPresenceIndicator: true,
                    isOnline: isOnline
                )
            }

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationScale)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationScale
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(.leading, 8)
        .onAppear {
            animationScale = 1.2
        }
    }

    @State private var animationScale: CGFloat = 0.8
}

private struct ComposerView: View {
    @Binding var messageText: String
    let isSending: Bool
    let sendAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button(action: sendAction) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
            }
            .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Scheduling Intent Banner

struct SchedulingIntentBanner: View {
    let confidence: Double
    let onViewSuggestions: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    private var confidenceText: String {
        if confidence >= 0.8 {
            return "High confidence"
        } else if confidence >= 0.6 {
            return "Medium confidence"
        } else {
            return "Detected"
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .blue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(confidenceColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18))
                        .foregroundStyle(confidenceColor)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduling Intent Detected")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text(confidenceText)
                            .font(.caption)
                    }
                    .foregroundStyle(confidenceColor)
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onSnooze) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("Snooze 1h")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.secondary)
                    .cornerRadius(8)
                }

                Button(action: onViewSuggestions) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text("View Suggestions")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(confidenceColor)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - TypingBubble Component
private struct TypingBubble: View {
    let displayName: String
    let isGroupChat: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Show name for group chats
            if isGroupChat {
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Animated dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: true
                        )
                        .offset(y: animationOffset(for: index))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(16)
        }
        .accessibilityLabel(isGroupChat ? "\(displayName) is typing" : "User is typing")
    }

    @State private var isAnimating = false

    private func animationOffset(for index: Int) -> CGFloat {
        isAnimating ? -4 : 0
    }

    init(displayName: String, isGroupChat: Bool) {
        self.displayName = displayName
        self.isGroupChat = isGroupChat
        _isAnimating = State(initialValue: true)
    }
}
