//
//  NetworkMonitor.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 10/23/25.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected: Bool = true
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    nonisolated deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
