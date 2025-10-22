//
//  PresenceStatus+UI.swift
//  messageai-swift
//
//  Created by Nick Kenkel on 11/19/25.
//

import SwiftUI

extension PresenceStatus {
    var sortRank: Int {
        switch self {
        case .online:
            return 0
        case .away:
            return 1
        case .offline:
            return 2
        }
    }

    var indicatorColor: Color {
        switch self {
        case .online:
            return .green
        case .away:
            return .orange
        case .offline:
            return .gray
        }
    }

    var displayLabel: String {
        switch self {
        case .online:
            return "Online"
        case .away:
            return "Away"
        case .offline:
            return "Offline"
        }
    }
}
