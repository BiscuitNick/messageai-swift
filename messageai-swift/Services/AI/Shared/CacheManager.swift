//
//  CacheManager.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation

/// Protocol for cacheable items with expiration support
protocol Cacheable {
    var cachedAt: Date { get }
    var isExpired: Bool { get }
}

/// Generic cache manager for AI feature responses
@MainActor
final class CacheManager<T: Cacheable> {

    // MARK: - Properties

    private var cache: [String: T] = [:]

    // MARK: - Public API

    /// Get a cached value if it exists and is not expired
    /// - Parameter key: The cache key
    /// - Returns: Cached value if valid, nil otherwise
    func get(_ key: String) -> T? {
        guard let cached = cache[key], !cached.isExpired else {
            cache.removeValue(forKey: key)
            return nil
        }
        return cached
    }

    /// Set a value in the cache
    /// - Parameters:
    ///   - key: The cache key
    ///   - value: The value to cache
    func set(_ key: String, value: T) {
        cache[key] = value
    }

    /// Remove a specific cached value
    /// - Parameter key: The cache key to remove
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
    }

    /// Clear all cached values
    func clear() {
        cache.removeAll()
    }

    /// Remove all expired entries from the cache
    /// - Returns: Number of entries removed
    @discardableResult
    func clearExpired() -> Int {
        let expiredKeys = cache.filter { $0.value.isExpired }.map { $0.key }
        expiredKeys.forEach { cache.removeValue(forKey: $0) }
        return expiredKeys.count
    }

    /// Get count of cached items
    var count: Int {
        cache.count
    }

    /// Check if cache contains a key
    /// - Parameter key: The cache key
    /// - Returns: True if key exists and is not expired
    func contains(_ key: String) -> Bool {
        guard let cached = cache[key] else { return false }
        return !cached.isExpired
    }
}
