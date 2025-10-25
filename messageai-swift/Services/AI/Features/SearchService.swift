//
//  SearchService.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import SwiftData

/// Service responsible for semantic search features
@MainActor
@Observable
final class SearchService {

    // MARK: - Public State

    /// Global search loading state
    var isLoading = false

    /// Global search error message
    var errorMessage: String?

    // MARK: - Dependencies

    private let functionClient: FirebaseFunctionClient
    private let telemetryLogger: TelemetryLogger
    private weak var authService: AuthService?
    private weak var modelContext: ModelContext?

    // MARK: - Cache

    private let cache: CacheManager<CachedSearchResults>

    // MARK: - Initialization

    init(
        functionClient: FirebaseFunctionClient,
        telemetryLogger: TelemetryLogger
    ) {
        self.functionClient = functionClient
        self.telemetryLogger = telemetryLogger
        self.cache = CacheManager<CachedSearchResults>()
    }

    // MARK: - Configuration

    func configure(
        authService: AuthService,
        modelContext: ModelContext
    ) {
        self.authService = authService
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Perform semantic search across user's conversations
    /// - Parameters:
    ///   - query: Search query text
    ///   - maxResults: Maximum number of results to return (default: 20)
    ///   - forceRefresh: Force a new search even if cache is valid (default: false)
    /// - Returns: Array of SearchResultEntity instances
    /// - Throws: AIFeaturesError or network errors
    func search(
        query: String,
        maxResults: Int = 20,
        forceRefresh: Bool = false
    ) async throws -> [SearchResultEntity] {
        // Verify user is authenticated
        guard let userId = authService?.currentUser?.id else {
            errorMessage = AIFeaturesError.unauthorized.errorDescription
            throw AIFeaturesError.unauthorized
        }

        // Validate query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw AIFeaturesError.invalidResponse
        }

        // Set loading state
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        // Check in-memory cache first unless force refresh is requested
        if !forceRefresh, let cached = cache.get(trimmedQuery) {
            #if DEBUG
            print("[SearchService] Returning in-memory cached search results for query: \(trimmedQuery)")
            #endif

            // Log cache hit to telemetry
            telemetryLogger.logSuccess(
                functionName: "smartSearch",
                userId: userId,
                startTime: Date(),
                endTime: Date(),
                attemptCount: 1,
                cacheHit: true
            )

            return cached.results
        }

        // Try to load from local SwiftData storage if not in memory cache
        if !forceRefresh, let localResults = fetchSearchResults(for: trimmedQuery) {
            #if DEBUG
            print("[SearchService] Returning local search results for query: \(trimmedQuery) (\(localResults.count) results)")
            #endif
            // Update memory cache
            cache.set(trimmedQuery, value: CachedSearchResults(
                query: trimmedQuery,
                results: localResults,
                cachedAt: Date()
            ))
            return localResults
        }

        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        do {
            // Prepare the request payload
            let payload: [String: Any] = [
                "query": trimmedQuery,
                "maxResults": maxResults,
            ]

            // Define response structure matching Firebase function output
            struct SmartSearchFirebaseResponse: Codable {
                let groupedResults: [GroupedResult]
                let query: String
                let totalHits: Int

                struct GroupedResult: Codable {
                    let conversationId: String
                    let hits: [Hit]
                }

                struct Hit: Codable {
                    let id: String
                    let conversationId: String
                    let messageId: String
                    let snippet: String
                    let rank: Int
                    let timestamp: String
                }

                enum CodingKeys: String, CodingKey {
                    case groupedResults = "grouped_results"
                    case query
                    case totalHits = "total_hits"
                }
            }

            // Call the Firebase Cloud Function
            let response: SmartSearchFirebaseResponse = try await functionClient.call(
                "smartSearch",
                payload: payload,
                userId: userId
            )

            // Delete any existing search results for this query (including expired ones)
            let existingDescriptor = FetchDescriptor<SearchResultEntity>(
                predicate: #Predicate { $0.query == trimmedQuery }
            )
            if let existingResults = try? modelContext.fetch(existingDescriptor) {
                for existing in existingResults {
                    modelContext.delete(existing)
                }
            }

            // Transform to SearchResultEntity instances
            var searchResults: [SearchResultEntity] = []

            for group in response.groupedResults {
                for hit in group.hits {
                    // Parse timestamp
                    let formatter = ISO8601DateFormatter()
                    let timestamp = formatter.date(from: hit.timestamp) ?? Date()

                    let entity = SearchResultEntity(
                        query: trimmedQuery,
                        conversationId: hit.conversationId,
                        messageId: hit.messageId,
                        snippet: hit.snippet,
                        rank: hit.rank,
                        timestamp: timestamp
                    )

                    searchResults.append(entity)
                    modelContext.insert(entity)
                }
            }

            // Save to SwiftData
            try modelContext.save()

            // Save recent query
            let recentQuery = RecentQueryEntity(
                query: trimmedQuery,
                searchedAt: Date(),
                resultCount: searchResults.count
            )
            modelContext.insert(recentQuery)
            try modelContext.save()

            // Update memory cache
            cache.set(trimmedQuery, value: CachedSearchResults(
                query: trimmedQuery,
                results: searchResults,
                cachedAt: Date()
            ))

            #if DEBUG
            print("[SearchService] Smart search completed: \(searchResults.count) results for query '\(trimmedQuery)'")
            #endif

            return searchResults
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Cache Management

    /// Clear all in-memory caches and SwiftData search results
    func clearCache() {
        cache.clear()
        isLoading = false
        errorMessage = nil
        clearSearchDataFromSwiftData()
    }

    // MARK: - SwiftData Persistence

    /// Fetch search results from local storage for a given query
    private func fetchSearchResults(for query: String) -> [SearchResultEntity]? {
        guard let modelContext = modelContext else { return nil }

        let descriptor = FetchDescriptor<SearchResultEntity>(
            predicate: #Predicate { $0.query == query },
            sortBy: [SortDescriptor(\.rank)]
        )

        guard let results = try? modelContext.fetch(descriptor), !results.isEmpty else {
            return nil
        }

        // Filter out expired results
        let validResults = results.filter { !$0.isExpired }

        if validResults.isEmpty {
            #if DEBUG
            print("[SearchService] All search results for '\(query)' expired, returning nil")
            #endif
            return nil
        }

        return validResults
    }

    /// Clear search-related data from SwiftData (search results and recent queries)
    private func clearSearchDataFromSwiftData() {
        guard let modelContext = modelContext else { return }

        do {
            // Delete all SearchResultEntity instances
            let searchDescriptor = FetchDescriptor<SearchResultEntity>()
            let searchResults = try modelContext.fetch(searchDescriptor)
            for result in searchResults {
                modelContext.delete(result)
            }

            // Delete all RecentQueryEntity instances
            let queryDescriptor = FetchDescriptor<RecentQueryEntity>()
            let recentQueries = try modelContext.fetch(queryDescriptor)
            for query in recentQueries {
                modelContext.delete(query)
            }

            try modelContext.save()

            #if DEBUG
            print("[SearchService] Cleared \(searchResults.count) search results and \(recentQueries.count) recent queries from SwiftData")
            #endif
        } catch {
            print("[SearchService] Error clearing search data: \(error.localizedDescription)")
        }
    }

    /// Clear expired search results from local storage
    func clearExpiredResults() throws {
        guard let modelContext = modelContext else {
            throw AIFeaturesError.notConfigured
        }

        let descriptor = FetchDescriptor<SearchResultEntity>()
        let allResults = try modelContext.fetch(descriptor)

        var deletedCount = 0
        for result in allResults where result.isExpired {
            modelContext.delete(result)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
            #if DEBUG
            print("[SearchService] Cleared \(deletedCount) expired search results")
            #endif
        }
    }
}

// MARK: - Cache Model

/// Cached search results entry with expiration
struct CachedSearchResults: Cacheable {
    let query: String
    let results: [SearchResultEntity]
    let cachedAt: Date

    var isExpired: Bool {
        // Cache expires after 1 hour
        Date().timeIntervalSince(cachedAt) > 3600
    }
}
