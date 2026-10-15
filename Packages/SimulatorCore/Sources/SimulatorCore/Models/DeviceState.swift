//
//  DeviceState.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

public enum DeviceState: Int, Decodable, Sendable {
    case off = 1
    case running = 3
    
    public var stateDescription: String {
        switch self {
        case .off:
            return "Off"
        case .running:
            return "Running"
        }
    }
}
