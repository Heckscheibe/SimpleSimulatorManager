//
//  AppChange.swift
//  SimulatorManager
//
//  Created by Hiller, Nicolas (CDA) on 22.07.25.
//

import Foundation

// MARK: - AppChange Types

struct AppChange: Hashable {
    let app: any SimulatorApp
    let device: Device
    let changeType: ChangeType
    let timestamp: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(app.bundleIdentifier)
        hasher.combine(device.udid)
        hasher.combine(changeType)
        hasher.combine(timestamp)
    }
    
    static func == (lhs: AppChange, rhs: AppChange) -> Bool {
        lhs.app.bundleIdentifier == rhs.app.bundleIdentifier &&
            lhs.device.udid == rhs.device.udid &&
            lhs.changeType == rhs.changeType &&
            lhs.timestamp == rhs.timestamp
    }
}

enum ChangeType {
    case installed
    case updated
    case removed
}

// MARK: - Extensions

extension AppChange: Identifiable {
    var id: String {
        "\(app.bundleIdentifier)-\(device.udid)-\(timestamp.timeIntervalSince1970)"
    }
}
