//
//  NetworkSimulator.swift
//  messageai-swift
//
//  Created for Task 7 on 10/24/25.
//

import Foundation
import Observation

/// Network condition profiles for simulation
enum NetworkCondition: String, CaseIterable, Codable {
    case normal
    case poor
    case veryPoor
    case offline

    /// Configuration for network condition
    struct Profile {
        let latencyRange: ClosedRange<Double>  // in seconds
        let dropRate: Double  // probability of packet loss (0.0 - 1.0)
    }

    var profile: Profile {
        switch self {
        case .normal:
            return Profile(latencyRange: 0.0...0.1, dropRate: 0.0)
        case .poor:
            return Profile(latencyRange: 0.5...1.5, dropRate: 0.1)
        case .veryPoor:
            return Profile(latencyRange: 2.0...5.0, dropRate: 0.3)
        case .offline:
            return Profile(latencyRange: 0.0...0.0, dropRate: 1.0)
        }
    }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .poor: return "Poor (500-1500ms, 10% loss)"
        case .veryPoor: return "Very Poor (2-5s, 30% loss)"
        case .offline: return "Offline"
        }
    }
}

/// Errors that can be thrown by network simulation
enum NetworkSimulatorError: Error, LocalizedError {
    case offline
    case simulatedFailure
    case wifiDisabled

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Device is offline"
        case .simulatedFailure:
            return "Network request failed due to simulated packet loss"
        case .wifiDisabled:
            return "WiFi is disabled"
        }
    }
}

/// Service to simulate various network conditions for debugging
@MainActor
@Observable
final class NetworkSimulator {
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let condition = "NetworkSimulator.condition"
        static let wifiEnabled = "NetworkSimulator.wifiEnabled"
        static let simulationEnabled = "NetworkSimulator.enabled"
    }

    // MARK: - Published State
    var currentCondition: NetworkCondition {
        didSet {
            saveSettings()
        }
    }

    var wifiEnabled: Bool {
        didSet {
            saveSettings()
        }
    }

    var simulationEnabled: Bool {
        didSet {
            saveSettings()
        }
    }

    // MARK: - Private Properties
    private let userDefaults: UserDefaults

    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load persisted settings
        if let conditionRaw = userDefaults.string(forKey: Keys.condition),
           let condition = NetworkCondition(rawValue: conditionRaw) {
            self.currentCondition = condition
        } else {
            self.currentCondition = .normal
        }

        self.wifiEnabled = userDefaults.bool(forKey: Keys.wifiEnabled)
        // Default to true if key doesn't exist
        if userDefaults.object(forKey: Keys.wifiEnabled) == nil {
            self.wifiEnabled = true
        }

        self.simulationEnabled = userDefaults.bool(forKey: Keys.simulationEnabled)
        // Default to false (simulation off by default)
    }

    // MARK: - Public Methods

    /// Execute an async operation with simulated network conditions
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: NetworkSimulatorError or errors from the operation
    func execute<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        // If simulation is disabled, run operation normally
        guard simulationEnabled else {
            return try await operation()
        }

        // Check WiFi state
        guard wifiEnabled else {
            throw NetworkSimulatorError.wifiDisabled
        }

        let profile = currentCondition.profile

        // Simulate latency
        let delay = Double.random(in: profile.latencyRange)
        if delay > 0 {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }

        // Simulate packet loss
        if Double.random(in: 0...1) < profile.dropRate {
            throw NetworkSimulatorError.simulatedFailure
        }

        // Execute the actual operation
        return try await operation()
    }

    /// Reset to default settings
    func reset() {
        currentCondition = .normal
        wifiEnabled = true
        simulationEnabled = false
    }

    // MARK: - Private Methods

    private func saveSettings() {
        userDefaults.set(currentCondition.rawValue, forKey: Keys.condition)
        userDefaults.set(wifiEnabled, forKey: Keys.wifiEnabled)
        userDefaults.set(simulationEnabled, forKey: Keys.simulationEnabled)
    }
}
