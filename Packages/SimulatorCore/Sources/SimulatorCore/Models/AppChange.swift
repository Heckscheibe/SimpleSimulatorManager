//
//  AppChange.swift
//  SimulatorManager
//
//  Created by Hiller, Nicolas (CDA) on 22.07.25.
//

import Foundation

// MARK: - AppChange Types

public struct AppChange: Hashable, Sendable {
    public let app: any SimulatorApp
    public let device: Device
    public let changeType: ChangeType
    public let timestamp: Date
    /// Whether the app's `.app` bundle was written for this change, as opposed to only its data
    /// container. An `.updated` change is raised whenever `contentModifiedAt` moves, and that includes
    /// a running app writing to its container; nothing was reinstalled then, so nothing should be
    /// described as an update. Not part of the change's identity.
    public var replacedBundle: Bool = true
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(app.bundleIdentifier)
        hasher.combine(device.udid)
        hasher.combine(changeType)
        hasher.combine(timestamp)
    }
    
    public static func == (lhs: AppChange, rhs: AppChange) -> Bool {
        lhs.app.bundleIdentifier == rhs.app.bundleIdentifier &&
            lhs.device.udid == rhs.device.udid &&
            lhs.changeType == rhs.changeType &&
            lhs.timestamp == rhs.timestamp
    }
}

public enum ChangeType: Sendable {
    case installed
    case updated
    case removed
}

// MARK: - Extensions

extension AppChange: Identifiable {
    public var id: String {
        "\(app.bundleIdentifier)-\(device.udid)-\(timestamp.timeIntervalSince1970)"
    }
}
