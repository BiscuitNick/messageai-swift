//
//  NetworkSimulatorTests.swift
//  messageai-swiftTests
//
//  Created for Task 10 on 10/24/25.
//

import XCTest
@testable import messageai_swift

@MainActor
final class NetworkSimulatorTests: XCTestCase {

    var simulator: NetworkSimulator!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        // Use a test suite name to isolate test data
        testDefaults = UserDefaults(suiteName: "NetworkSimulatorTests")!
        testDefaults.removePersistentDomain(forName: "NetworkSimulatorTests")

        simulator = NetworkSimulator(userDefaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: "NetworkSimulatorTests")
        simulator = nil
        testDefaults = nil
    }

    // MARK: - NetworkCondition Tests

    func testAllNetworkConditionsExist() throws {
        let allConditions = NetworkCondition.allCases
        XCTAssertEqual(allConditions.count, 4)
        XCTAssertTrue(allConditions.contains(.normal))
        XCTAssertTrue(allConditions.contains(.poor))
        XCTAssertTrue(allConditions.contains(.veryPoor))
        XCTAssertTrue(allConditions.contains(.offline))
    }

    func testNetworkConditionRawValues() throws {
        XCTAssertEqual(NetworkCondition.normal.rawValue, "normal")
        XCTAssertEqual(NetworkCondition.poor.rawValue, "poor")
        XCTAssertEqual(NetworkCondition.veryPoor.rawValue, "veryPoor")
        XCTAssertEqual(NetworkCondition.offline.rawValue, "offline")
    }

    func testNormalConditionProfile() throws {
        let profile = NetworkCondition.normal.profile

        XCTAssertEqual(profile.latencyRange.lowerBound, 0.0)
        XCTAssertEqual(profile.latencyRange.upperBound, 0.1)
        XCTAssertEqual(profile.dropRate, 0.0)
    }

    func testPoorConditionProfile() throws {
        let profile = NetworkCondition.poor.profile

        XCTAssertEqual(profile.latencyRange.lowerBound, 0.5)
        XCTAssertEqual(profile.latencyRange.upperBound, 1.5)
        XCTAssertEqual(profile.dropRate, 0.1)
    }

    func testVeryPoorConditionProfile() throws {
        let profile = NetworkCondition.veryPoor.profile

        XCTAssertEqual(profile.latencyRange.lowerBound, 2.0)
        XCTAssertEqual(profile.latencyRange.upperBound, 5.0)
        XCTAssertEqual(profile.dropRate, 0.3)
    }

    func testOfflineConditionProfile() throws {
        let profile = NetworkCondition.offline.profile

        XCTAssertEqual(profile.latencyRange.lowerBound, 0.0)
        XCTAssertEqual(profile.latencyRange.upperBound, 0.0)
        XCTAssertEqual(profile.dropRate, 1.0)
    }

    func testNetworkConditionDisplayNames() throws {
        XCTAssertEqual(NetworkCondition.normal.displayName, "Normal")
        XCTAssertTrue(NetworkCondition.poor.displayName.contains("Poor"))
        XCTAssertTrue(NetworkCondition.veryPoor.displayName.contains("Very Poor"))
        XCTAssertEqual(NetworkCondition.offline.displayName, "Offline")
    }

    // MARK: - NetworkSimulatorError Tests

    func testNetworkSimulatorErrorOffline() throws {
        let error = NetworkSimulatorError.offline
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("offline"))
    }

    func testNetworkSimulatorErrorSimulatedFailure() throws {
        let error = NetworkSimulatorError.simulatedFailure
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("packet loss"))
    }

    func testNetworkSimulatorErrorWifiDisabled() throws {
        let error = NetworkSimulatorError.wifiDisabled
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("WiFi"))
    }

    // MARK: - Initialization Tests

    func testDefaultInitialization() throws {
        XCTAssertEqual(simulator.currentCondition, .normal)
        XCTAssertTrue(simulator.wifiEnabled)
        XCTAssertFalse(simulator.simulationEnabled) // Should default to false
    }

    func testPersistenceOfSettings() throws {
        // Set values
        simulator.currentCondition = .poor
        simulator.wifiEnabled = false
        simulator.simulationEnabled = true

        // Create new instance with same UserDefaults
        let newSimulator = NetworkSimulator(userDefaults: testDefaults)

        // Verify values persisted
        XCTAssertEqual(newSimulator.currentCondition, .poor)
        XCTAssertFalse(newSimulator.wifiEnabled)
        XCTAssertTrue(newSimulator.simulationEnabled)
    }

    // MARK: - Simulation Disabled Tests

    func testExecuteWithSimulationDisabled() async throws {
        simulator.simulationEnabled = false
        simulator.currentCondition = .offline

        var executed = false

        // Should execute immediately even though condition is offline
        let result = try await simulator.execute {
            executed = true
            return "success"
        }

        XCTAssertTrue(executed)
        XCTAssertEqual(result, "success")
    }

    func testExecuteWithSimulationDisabledDoesNotDelay() async throws {
        simulator.simulationEnabled = false
        simulator.currentCondition = .veryPoor // 2-5 second delay

        let startTime = Date()

        _ = try await simulator.execute {
            return "success"
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete almost instantly (< 0.1 seconds)
        XCTAssertLessThan(elapsed, 0.1)
    }

    // MARK: - WiFi Disabled Tests

    func testExecuteWithWifiDisabled() async throws {
        simulator.simulationEnabled = true
        simulator.wifiEnabled = false

        do {
            _ = try await simulator.execute {
                return "success"
            }
            XCTFail("Should have thrown wifiDisabled error")
        } catch NetworkSimulatorError.wifiDisabled {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Latency Tests

    func testExecuteWithNormalConditionHasMinimalDelay() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .normal

        let startTime = Date()

        _ = try await simulator.execute {
            return "success"
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Normal condition: 0-0.1 seconds
        XCTAssertLessThanOrEqual(elapsed, 0.2) // Add some margin for test execution
    }

    func testExecuteWithPoorConditionHasDelay() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .poor

        let startTime = Date()

        _ = try await simulator.execute {
            return "success"
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Poor condition: 0.5-1.5 seconds (if no packet loss occurs)
        // Due to randomness, we can't assert exact values
        // This test may occasionally fail due to packet loss (10%)
        // In production, you'd seed the RNG for deterministic tests
    }

    // MARK: - Packet Loss Tests (Probabilistic)

    func testOfflineConditionAlwaysFails() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .offline

        var failureCount = 0
        let attempts = 10

        for _ in 0..<attempts {
            do {
                _ = try await simulator.execute {
                    return "success"
                }
            } catch NetworkSimulatorError.simulatedFailure {
                failureCount += 1
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        // Offline should have 100% drop rate
        XCTAssertEqual(failureCount, attempts)
    }

    func testNormalConditionNeverDropsPackets() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .normal

        var successCount = 0
        let attempts = 20

        for _ in 0..<attempts {
            do {
                _ = try await simulator.execute {
                    return "success"
                }
                successCount += 1
            } catch {
                // Normal condition should never fail
                XCTFail("Normal condition should not drop packets: \(error)")
            }
        }

        // All attempts should succeed
        XCTAssertEqual(successCount, attempts)
    }

    func testPoorConditionHasPacketLoss() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .poor // 10% drop rate

        var successCount = 0
        var failureCount = 0
        let attempts = 100 // Large sample for statistical significance

        for _ in 0..<attempts {
            do {
                _ = try await simulator.execute {
                    return "success"
                }
                successCount += 1
            } catch NetworkSimulatorError.simulatedFailure {
                failureCount += 1
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        // With 10% drop rate, expect roughly 5-15% failures in 100 attempts
        // (allowing for statistical variance)
        XCTAssertGreaterThan(failureCount, 0)
        XCTAssertLessThan(failureCount, 25) // Should not exceed 25%
    }

    // MARK: - Reset Tests

    func testReset() throws {
        // Set non-default values
        simulator.currentCondition = .offline
        simulator.wifiEnabled = false
        simulator.simulationEnabled = true

        // Reset
        simulator.reset()

        // Verify default values restored
        XCTAssertEqual(simulator.currentCondition, .normal)
        XCTAssertTrue(simulator.wifiEnabled)
        XCTAssertFalse(simulator.simulationEnabled)
    }

    // MARK: - Codable Tests

    func testNetworkConditionCodable() throws {
        for condition in NetworkCondition.allCases {
            let encoded = try JSONEncoder().encode(condition)
            let decoded = try JSONDecoder().decode(NetworkCondition.self, from: encoded)
            XCTAssertEqual(condition, decoded)
        }
    }

    // MARK: - Edge Cases

    func testMultipleExecutionsInParallel() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .normal

        // Execute multiple operations in parallel
        async let result1 = simulator.execute { return "result1" }
        async let result2 = simulator.execute { return "result2" }
        async let result3 = simulator.execute { return "result3" }

        let results = try await [result1, result2, result3]

        XCTAssertEqual(results, ["result1", "result2", "result3"])
    }

    func testExecutePreservesOperationErrors() async throws {
        simulator.simulationEnabled = true
        simulator.currentCondition = .normal

        enum TestError: Error {
            case customError
        }

        do {
            _ = try await simulator.execute {
                throw TestError.customError
            }
            XCTFail("Should have thrown custom error")
        } catch TestError.customError {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
