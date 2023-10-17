//
//  DeviceType.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

struct DeviceType: Comparable, Hashable, Identifiable {
    let id: String
    
    var name: String {
        id
    }
    
    static func < (lhs: DeviceType, rhs: DeviceType) -> Bool {
        return lhs.id < rhs.id
    }
}
