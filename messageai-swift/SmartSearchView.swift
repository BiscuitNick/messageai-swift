//
//  SmartSearchView.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import SwiftUI
import SwiftData

struct SmartSearchView: View {
    var onNavigate: ((SearchNavigationTarget) -> Void)?

    @Environment(AIFeaturesService.self) private var aiFeaturesService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResultEntity] = []
    @State private var recentQueries: [RecentQueryEntity] = []
    @State private var showingResults = false

    @Query(sort: \RecentQueryEntity.searchedAt, order: .reverse)
    private var allRecentQueries: [RecentQueryEntity]

    // Group results by conversation
    private var groupedResults: [(conversationId: String, results: [SearchResultEntity])] {
        let groups = Dictionary(grouping: searchResults) { $0.conversationId }
        return groups.map { (conversationId: $0.key, results: $0.value.sorted { $0.rank < $1.rank }) }
            .sorted { $0.results.first?.rank ?? 0 < $1.results.first?.rank ?? 0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Content
                if aiFeaturesService.searchLoadingState {
                    loadingView
                } else if let error = aiFeaturesService.searchError {
                    errorView(error)
                } else if showingResults && searchResults.isEmpty {
                    emptyResultsView
                } else if showingResults {
                    resultsView
                } else {
                    recentQueriesView
                }
            }
            .navigationTitle("Smart Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            recentQueries = Array(allRecentQueries.prefix(10))
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search conversations...", text: $searchQuery)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    showingResults = false
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching conversations...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Search Failed")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                performSearch()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Results Found")
                .font(.headline)
            Text("Try different keywords or check your spelling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var recentQueriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !recentQueries.isEmpty {
                    Text("Recent Searches")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    ForEach(recentQueries) { query in
                        Button {
                            searchQuery = query.query
                            performSearch()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(query.query)
                                        .foregroundStyle(.primary)
                                    Text("\(query.resultCount) results")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.backward")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Search Your Conversations")
                            .font(.headline)
                        Text("Use semantic search to find messages across all your conversations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedResults, id: \.conversationId) { group in
                    Section {
                        ForEach(group.results) { result in
                            SearchResultRow(result: result, onNavigate: onNavigate)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                        }
                    } header: {
                        HStack {
                            Text("Conversation")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.results.count)")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        showingResults = true

        Task {
            do {
                let results = try await aiFeaturesService.smartSearch(query: searchQuery)
                await MainActor.run {
                    searchResults = results
                    recentQueries = Array(allRecentQueries.prefix(10))
                }
            } catch {
                print("[SmartSearchView] Search failed: \(error)")
            }
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResultEntity
    var onNavigate: ((SearchNavigationTarget) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    private var conversation: ConversationEntity? {
        conversations.first { $0.id == result.conversationId }
    }

    private var conversationTitle: String {
        guard let conv = conversation else {
            return "Unknown Conversation"
        }

        if conv.isGroup {
            return conv.groupName ?? "Group Chat"
        } else {
            // Get the other participant's name for DM
            // This is simplified - in production you'd fetch the other user's displayName
            return "Direct Message"
        }
    }

    var body: some View {
        Button {
            onNavigate?(SearchNavigationTarget(
                conversationId: result.conversationId,
                messageId: result.messageId
            ))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Conversation info
                HStack {
                    Text(conversationTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Rank badge
                    Text("#\(result.rank)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }

                // Snippet
                Text(result.snippet)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                // Timestamp
                Text(result.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// Navigation target for search results
struct SearchNavigationTarget: Hashable {
    let conversationId: String
    let messageId: String
}
