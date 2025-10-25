//
//  TelemetryLogger.swift
//  messageai-swift
//
//  Created by Claude Code on 2025-10-24.
//

import Foundation
import FirebaseFirestore

/// Telemetry logging service for AI feature calls
@MainActor
final class TelemetryLogger {

    // MARK: - Properties

    private let firestore = Firestore.firestore()

    /// Enable/disable telemetry logging (can be controlled by user settings or build config)
    var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "ai_telemetry_enabled")
        #endif
    }

    // MARK: - Public API

    /// Log a successful AI function call
    /// - Parameters:
    ///   - functionName: Name of the function called
    ///   - userId: User ID (optional)
    ///   - startTime: When the call started
    ///   - endTime: When the call completed
    ///   - attemptCount: Number of attempts made
    ///   - cacheHit: Whether this was a cache hit
    func logSuccess(
        functionName: String,
        userId: String?,
        startTime: Date,
        endTime: Date,
        attemptCount: Int = 1,
        cacheHit: Bool = false
    ) {
        let event = TelemetryEvent(
            userId: userId,
            functionName: functionName,
            startTime: startTime,
            endTime: endTime,
            success: true,
            attemptCount: attemptCount,
            cacheHit: cacheHit
        )
        logEvent(event)
    }

    /// Log a failed AI function call
    /// - Parameters:
    ///   - functionName: Name of the function called
    ///   - userId: User ID (optional)
    ///   - startTime: When the call started
    ///   - endTime: When the call failed
    ///   - error: The error that occurred
    ///   - attemptCount: Number of attempts made
    func logFailure(
        functionName: String,
        userId: String?,
        startTime: Date,
        endTime: Date,
        error: Error,
        attemptCount: Int = 1
    ) {
        let event = TelemetryEvent(
            userId: userId,
            functionName: functionName,
            startTime: startTime,
            endTime: endTime,
            success: false,
            attemptCount: attemptCount,
            errorType: String(describing: type(of: error)),
            errorMessage: error.localizedDescription
        )
        logEvent(event)
    }

    // MARK: - Private Implementation

    /// Log telemetry event to Firestore analytics collection
    private func logEvent(_ event: TelemetryEvent) {
        guard isEnabled else { return }

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let collectionRef = firestore.collection("ai_telemetry")
                try await collectionRef.document(event.eventId).setData(event.toDictionary())

                #if DEBUG
                print("[TelemetryLogger] Logged: \(event.functionName) - \(event.success ? "success" : "failure") in \(event.durationMs)ms (attempts: \(event.attemptCount))")
                #endif
            } catch {
                #if DEBUG
                print("[TelemetryLogger] Failed to log telemetry: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

// MARK: - Telemetry Event Model

/// Telemetry event capturing AI call metrics
private struct TelemetryEvent: Codable {
    let eventId: String
    let userId: String?
    let functionName: String
    let startTime: Date
    let endTime: Date
    let durationMs: Int
    let success: Bool
    let attemptCount: Int
    let errorType: String?
    let errorMessage: String?
    let cacheHit: Bool
    let timestamp: Date

    init(
        userId: String?,
        functionName: String,
        startTime: Date,
        endTime: Date,
        success: Bool,
        attemptCount: Int,
        errorType: String? = nil,
        errorMessage: String? = nil,
        cacheHit: Bool = false
    ) {
        self.eventId = UUID().uuidString
        self.userId = userId
        self.functionName = functionName
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
        self.success = success
        self.attemptCount = attemptCount
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.cacheHit = cacheHit
        self.timestamp = Date()
    }

    func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
