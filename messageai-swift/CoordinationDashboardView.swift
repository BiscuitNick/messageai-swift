//
//  CoordinationDashboardView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData

struct CoordinationDashboardView: View {
    @Environment(AIFeaturesService.self) private var aiFeaturesService
    @Environment(\.modelContext) private var modelContext

    @Query(
        sort: [SortDescriptor(\CoordinationInsightEntity.generatedAt, order: .reverse)]
    )
    private var allInsights: [CoordinationInsightEntity]

    // Filter out expired insights (computed property can't be used in @Query predicate)
    private var insights: [CoordinationInsightEntity] {
        allInsights.filter { !$0.isExpired }
    }

    @Query(
        sort: [
            SortDescriptor(\ProactiveAlertEntity.severityRawValue, order: .reverse),
            SortDescriptor(\ProactiveAlertEntity.createdAt, order: .reverse)
        ]
    )
    private var allAlerts: [ProactiveAlertEntity]

    // Filter to only active alerts (computed property can't be used in @Query predicate)
    private var alerts: [ProactiveAlertEntity] {
        allAlerts.filter { $0.isActive }
    }

    @Query private var conversations: [ConversationEntity]

    @State private var isRefreshing = false
    @State private var selectedInsight: CoordinationInsightEntity?

    var body: some View {
        NavigationStack {
            Group {
                if insights.isEmpty && alerts.isEmpty {
                    emptyStateView
                } else {
                    List {
                        if !alerts.isEmpty {
                            alertsSection
                        }

                        if !insights.isEmpty {
                            overallHealthSection

                            if hasActionItems {
                                actionItemsSection
                            }

                            if hasStaleDecisions {
                                staleDecisionsSection
                            }

                            if hasSchedulingConflicts {
                                schedulingConflictsSection
                            }

                            if hasBlockers {
                                blockersSection
                            }

                            if hasUpcomingDeadlines {
                                upcomingDeadlinesSection
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Team Coordination")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refreshInsights()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .refreshable {
                await aiFeaturesService.refreshCoordinationInsights()
            }
        }
    }

    // MARK: - Alert Section

    private var alertsSection: some View {
        Section {
            ForEach(alerts) { alert in
                AlertRow(alert: alert, onDismiss: {
                    dismissAlert(alert)
                }, onMarkRead: {
                    markAlertAsRead(alert)
                })
            }
        } header: {
            HStack {
                Text("Proactive Alerts")
                Spacer()
                Text("\(alerts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Health Section

    private var overallHealthSection: some View {
        Section("Overall Health") {
            ForEach(insights) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    NavigationLink(destination: destinationView(for: insight, conversation: conversation)) {
                        HealthRow(insight: insight, conversationTitle: conversationTitle(for: conversation))
                    }
                } else {
                    HealthRow(insight: insight, conversationTitle: insight.conversationId)
                }
            }
        }
    }

    // MARK: - Action Items Section

    private var hasActionItems: Bool {
        insights.contains { !$0.actionItems.isEmpty }
    }

    private var actionItemsSection: some View {
        Section {
            ForEach(insights.filter { !$0.actionItems.isEmpty }) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    DisclosureGroup {
                        ForEach(insight.actionItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.description)
                                    .font(.subheadline)

                                if let assignee = item.assignee {
                                    Label(assignee, systemImage: "person.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let deadline = item.deadline {
                                    Label(deadline, systemImage: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                StatusBadge(status: item.status)
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversationTitle(for: conversation))
                                    .font(.headline)
                                Text("\(insight.actionItems.count) action items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Action Items", systemImage: "checkmark.circle.fill")
                Spacer()
                Text("\(totalActionItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stale Decisions Section

    private var hasStaleDecisions: Bool {
        insights.contains { !$0.staleDecisions.isEmpty }
    }

    private var staleDecisionsSection: some View {
        Section {
            ForEach(insights.filter { !$0.staleDecisions.isEmpty }) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    DisclosureGroup {
                        ForEach(insight.staleDecisions) { decision in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(decision.topic)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Last mentioned: \(decision.lastMentioned)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(decision.reason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversationTitle(for: conversation))
                                    .font(.headline)
                                Text("\(insight.staleDecisions.count) stale decisions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Stale Decisions", systemImage: "exclamationmark.triangle.fill")
                Spacer()
                Text("\(totalStaleDecisions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Scheduling Conflicts Section

    private var hasSchedulingConflicts: Bool {
        insights.contains { !$0.schedulingConflicts.isEmpty }
    }

    private var schedulingConflictsSection: some View {
        Section {
            ForEach(insights.filter { !$0.schedulingConflicts.isEmpty }) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    DisclosureGroup {
                        ForEach(insight.schedulingConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conflict.description)
                                    .font(.subheadline)

                                if !conflict.participants.isEmpty {
                                    HStack {
                                        Image(systemName: "person.2.fill")
                                            .font(.caption)
                                        Text(conflict.participants.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversationTitle(for: conversation))
                                    .font(.headline)
                                Text("\(insight.schedulingConflicts.count) conflicts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Scheduling Conflicts", systemImage: "calendar.badge.exclamationmark")
                Spacer()
                Text("\(totalSchedulingConflicts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Blockers Section

    private var hasBlockers: Bool {
        insights.contains { !$0.blockers.isEmpty }
    }

    private var blockersSection: some View {
        Section {
            ForEach(insights.filter { !$0.blockers.isEmpty }) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    DisclosureGroup {
                        ForEach(insight.blockers) { blocker in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(blocker.description)
                                    .font(.subheadline)

                                if let blockedBy = blocker.blockedBy {
                                    Label(blockedBy, systemImage: "hand.raised.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversationTitle(for: conversation))
                                    .font(.headline)
                                Text("\(insight.blockers.count) blockers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Blockers", systemImage: "hand.raised.fill")
                Spacer()
                Text("\(totalBlockers)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Upcoming Deadlines Section

    private var hasUpcomingDeadlines: Bool {
        insights.contains { !$0.upcomingDeadlines.isEmpty }
    }

    private var upcomingDeadlinesSection: some View {
        Section {
            ForEach(insights.filter { !$0.upcomingDeadlines.isEmpty }) { insight in
                if let conversation = conversations.first(where: { $0.id == insight.conversationId }) {
                    DisclosureGroup {
                        ForEach(insight.upcomingDeadlines) { deadline in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deadline.description)
                                    .font(.subheadline)

                                HStack {
                                    Label(deadline.dueDate, systemImage: "calendar")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    UrgencyBadge(urgency: deadline.urgency)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversationTitle(for: conversation))
                                    .font(.headline)
                                Text("\(insight.upcomingDeadlines.count) deadlines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Upcoming Deadlines", systemImage: "clock.badge.exclamationmark")
                Spacer()
                Text("\(totalUpcomingDeadlines)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("All Caught Up!")
                .font(.title2.bold())

            Text("No coordination issues detected.\nYour team is running smoothly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                refreshInsights()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func destinationView(for insight: CoordinationInsightEntity, conversation: ConversationEntity) -> some View {
        if let currentUser = try? modelContext.fetch(FetchDescriptor<UserEntity>()).first {
            let photoURL: URL? = if let urlString = currentUser.profilePictureURL {
                URL(string: urlString)
            } else {
                nil
            }

            ChatView(conversation: conversation, currentUser: AuthService.AppUser(
                id: currentUser.id,
                email: currentUser.email,
                displayName: currentUser.displayName,
                photoURL: photoURL
            ))
        } else {
            Text("Unable to load chat")
        }
    }

    // MARK: - Computed Properties

    private var totalActionItems: Int {
        insights.reduce(0) { $0 + $1.actionItems.count }
    }

    private var totalStaleDecisions: Int {
        insights.reduce(0) { $0 + $1.staleDecisions.count }
    }

    private var totalSchedulingConflicts: Int {
        insights.reduce(0) { $0 + $1.schedulingConflicts.count }
    }

    private var totalBlockers: Int {
        insights.reduce(0) { $0 + $1.blockers.count }
    }

    private var totalUpcomingDeadlines: Int {
        insights.reduce(0) { $0 + $1.upcomingDeadlines.count }
    }

    private func conversationTitle(for conversation: ConversationEntity) -> String {
        conversation.groupName ?? "Chat"
    }

    // MARK: - Actions

    private func refreshInsights() {
        isRefreshing = true
        Task {
            // Force new analysis when user manually taps refresh
            await aiFeaturesService.refreshCoordinationInsights(forceAnalysis: true)
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func dismissAlert(_ alert: ProactiveAlertEntity) {
        do {
            try aiFeaturesService.dismissAlert(alert.id)
        } catch {
            #if DEBUG
            print("[CoordinationDashboardView] Failed to dismiss alert: \(error.localizedDescription)")
            #endif
        }
    }

    private func markAlertAsRead(_ alert: ProactiveAlertEntity) {
        do {
            try aiFeaturesService.markAlertAsRead(alert.id)
        } catch {
            #if DEBUG
            print("[CoordinationDashboardView] Failed to mark alert as read: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Supporting Views

struct HealthRow: View {
    let insight: CoordinationInsightEntity
    let conversationTitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversationTitle)
                    .font(.headline)

                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Generated \(insight.generatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(insight.overallHealth.emoji)
                    .font(.title2)

                Text(insight.overallHealth.displayLabel)
                    .font(.caption)
                    .foregroundStyle(insight.overallHealth.color)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AlertRow: View {
    let alert: ProactiveAlertEntity
    let onDismiss: () -> Void
    let onMarkRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.severity.emoji)
                    Text(alert.title)
                        .font(.headline)
                        .fontWeight(alert.isRead ? .regular : .bold)
                }

                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(alert.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                if !alert.isRead {
                    Button {
                        onMarkRead()
                    } label: {
                        Label("Mark as Read", systemImage: "checkmark")
                    }
                }

                Button(role: .destructive) {
                    onDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status.lowercased() {
        case "resolved", "completed":
            return .green.opacity(0.2)
        case "pending":
            return .orange.opacity(0.2)
        case "unresolved":
            return .red.opacity(0.2)
        default:
            return .gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status.lowercased() {
        case "resolved", "completed":
            return .green
        case "pending":
            return .orange
        case "unresolved":
            return .red
        default:
            return .gray
        }
    }
}

struct UrgencyBadge: View {
    let urgency: String

    var body: some View {
        Text(urgency.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch urgency.lowercased() {
        case "critical":
            return .red.opacity(0.2)
        case "high":
            return .orange.opacity(0.2)
        case "medium":
            return .yellow.opacity(0.2)
        case "low":
            return .blue.opacity(0.2)
        default:
            return .gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch urgency.lowercased() {
        case "critical":
            return .red
        case "high":
            return .orange
        case "medium":
            return .yellow
        case "low":
            return .blue
        default:
            return .gray
        }
    }
}
