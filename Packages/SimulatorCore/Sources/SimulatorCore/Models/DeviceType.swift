//
//  DeviceType.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

public struct DeviceType: Comparable, Hashable, Identifiable, Sendable {
    public let id: String
    public let simulatorPlatform: SimulatorPlatform
    
    public var name: String {
        id
    }
    
    public static func < (lhs: DeviceType, rhs: DeviceType) -> Bool {
        return lhs.id < rhs.id
    }
}
