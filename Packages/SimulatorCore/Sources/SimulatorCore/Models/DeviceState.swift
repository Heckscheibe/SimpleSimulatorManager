//
//  DeviceState.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

/// The `state` CoreSimulator writes to `device.plist`. Every value it uses is modelled, so a
/// simulator that is mid-transition still decodes instead of disappearing from the list.
public enum DeviceState: Int, CaseIterable, Decodable, Sendable {
    case creating = 0
    case off = 1
    case booting = 2
    case running = 3
    case shuttingDown = 4
    
    public var stateDescription: String {
        switch self {
        case .creating:
            return "Creating"
        case .off:
            return "Off"
        case .booting:
            return "Booting"
        case .running:
            return "Running"
        case .shuttingDown:
            return "Shutting Down"
        }
    }
}
