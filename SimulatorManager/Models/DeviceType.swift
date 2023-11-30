//
//  DeviceType.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

struct DeviceType: Comparable, Hashable, Identifiable {
    let id: String
    let simulatorPlatform: SimulatorPlatform
    
    var name: String {
        id
    }
    
    static func < (lhs: DeviceType, rhs: DeviceType) -> Bool {
        return lhs.id < rhs.id
    }
}
