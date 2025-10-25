//
//  FirebaseFunctionClient.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFunctions
import FirebaseAuth

/// Shared client for calling Firebase Cloud Functions with retry logic
@MainActor
final class FirebaseFunctionClient {

    // MARK: - Properties

    private let functions = Functions.functions(region: "us-central1")
    private let telemetryLogger: TelemetryLogger

    // MARK: - Retry Configuration

    private enum RetryConfig {
        static let maxAttempts = 3
        static let baseDelayNanoseconds: UInt64 = 500_000_000 // 0.5 seconds
        static let maxDelayNanoseconds: UInt64 = 8_000_000_000 // 8 seconds
    }

    // MARK: - Initialization

    init(telemetryLogger: TelemetryLogger) {
        self.telemetryLogger = telemetryLogger
    }

    // MARK: - Public API

    /// Call a Firebase Cloud Function with exponential backoff retry
    /// - Parameters:
    ///   - name: Function name to invoke
    ///   - payload: Request payload as dictionary
    ///   - userId: User ID for telemetry (optional)
    /// - Returns: Decoded response of type T
    /// - Throws: Function call or decoding errors after all retries exhausted
    func call<T: Decodable>(
        _ name: String,
        payload: [String: Any] = [:],
        userId: String? = nil
    ) async throws -> T {
        try await callWithRetry(
            name: name,
            payload: payload,
            userId: userId
        )
    }

    // MARK: - Private Implementation

    private func callWithRetry<T: Decodable>(
        name: String,
        payload: [String: Any] = [:],
        userId: String? = nil,
        attempt: Int = 1,
        startTime: Date? = nil
    ) async throws -> T {

        // Track start time on first attempt
        let callStartTime = startTime ?? Date()

        do {
            // Force token refresh to ensure Firebase Auth has a valid token
            if let currentUser = Auth.auth().currentUser {
                do {
                    _ = try await currentUser.getIDToken(forcingRefresh: true)
                } catch {
                    print("[FirebaseFunctionClient] Token refresh failed: \(error.localizedDescription)")
                    // Continue anyway - might still work with cached token
                }
            }

            let result = try await functions.httpsCallable(name).call(payload)

            guard let data = result.data as? [String: Any] else {
                throw AIFeaturesError.invalidResponse
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)

            // Configure decoder to handle ISO8601 date strings from backend
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: jsonData)

            #if DEBUG
            if attempt > 1 {
                print("[FirebaseFunctionClient] '\(name)' succeeded on attempt \(attempt)")
            }
            #endif

            // Log successful telemetry
            telemetryLogger.logSuccess(
                functionName: name,
                userId: userId,
                startTime: callStartTime,
                endTime: Date(),
                attemptCount: attempt
            )

            return decoded
        } catch {
            let detailedError: String
            let shouldRetry = isRetryableError(error)

            if let decodingError = error as? DecodingError {
                detailedError = formatDecodingError(decodingError)
                print("[FirebaseFunctionClient] Decoding error for '\(name)': \(detailedError)")
            } else {
                detailedError = error.localizedDescription
                print("[FirebaseFunctionClient] Error calling '\(name)' (attempt \(attempt)/\(RetryConfig.maxAttempts)): \(detailedError)")
            }

            // Check if we should retry
            if shouldRetry && attempt < RetryConfig.maxAttempts {
                // Calculate exponential backoff delay
                let delayNanoseconds = calculateBackoffDelay(for: attempt)

                #if DEBUG
                print("[FirebaseFunctionClient] Retrying '\(name)' after \(Double(delayNanoseconds) / 1_000_000_000)s delay...")
                #endif

                // Wait before retry
                try await Task.sleep(nanoseconds: delayNanoseconds)

                // Recursive retry
                return try await callWithRetry(
                    name: name,
                    payload: payload,
                    userId: userId,
                    attempt: attempt + 1,
                    startTime: callStartTime
                )
            }

            // No more retries - log failure telemetry
            telemetryLogger.logFailure(
                functionName: name,
                userId: userId,
                startTime: callStartTime,
                endTime: Date(),
                error: error,
                attemptCount: attempt
            )

            throw error
        }
    }

    /// Determine if an error is retryable (network/transient errors)
    private func isRetryableError(_ error: Error) -> Bool {
        // Don't retry decoding errors - these indicate response schema issues
        if error is DecodingError {
            return false
        }

        // Don't retry invalid response errors - these indicate backend issues
        if let aiError = error as? AIFeaturesError, aiError == .invalidResponse {
            return false
        }

        // Check for NSError with network-related codes
        let nsError = error as NSError

        // Retry on network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }

        // Retry on Functions-specific errors (INTERNAL, UNAVAILABLE, DEADLINE_EXCEEDED)
        if nsError.domain == "FIRFunctionsErrorDomain" {
            // FunctionsErrorCode: internal = 13, unavailable = 14, deadlineExceeded = 4
            switch nsError.code {
            case 4, 13, 14:
                return true
            default:
                return false
            }
        }

        return false
    }

    /// Calculate exponential backoff delay with jitter
    private func calculateBackoffDelay(for attempt: Int) -> UInt64 {
        // Exponential backoff: base * 2^(attempt-1)
        let exponentialDelay = RetryConfig.baseDelayNanoseconds * UInt64(pow(2.0, Double(attempt - 1)))

        // Cap at max delay
        let cappedDelay = min(exponentialDelay, RetryConfig.maxDelayNanoseconds)

        // Add jitter (±25% randomness) to avoid thundering herd
        let jitterRange = Double(cappedDelay) * 0.25
        let jitter = Double.random(in: -jitterRange...jitterRange)
        let finalDelay = UInt64(max(0, Double(cappedDelay) + jitter))

        return finalDelay
    }

    /// Format a DecodingError into a human-readable message
    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }
}
