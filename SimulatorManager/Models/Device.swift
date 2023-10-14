//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

struct Runtime: Decodable {}

enum DeviceState: Int, Decodable {
    case off = 1
    case running = 3
}

struct Device: Decodable {
    enum CodingKeys: String, CodingKey {
        case udid = "UDID"
        case name
        case lastBootedAt
        case runtime
        case state
    }
    
    let udid: String
    let name: String
    let lastBootedAt: Date?
    let runtime: String
    let state: DeviceState
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.udid = try container.decode(String.self, forKey: .udid)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastBootedAt = try container.decodeIfPresent(Date.self, forKey: .lastBootedAt)
        
        let rawRuntimeString = try container.decode(String.self, forKey: .runtime)
        
        let lastComponent = rawRuntimeString.lastIndex(of: ".") ?? rawRuntimeString.endIndex
        let startingIndexOfOSVersion = rawRuntimeString.index(after: lastComponent)
        let osVersion = rawRuntimeString.suffix(from: startingIndexOfOSVersion).replacingOccurrences(of: "-", with: " ")
        
        os_log("OSVersion: \(osVersion)")
        self.runtime = String(osVersion)
        self.state = try container.decode(DeviceState.self, forKey: .state)
    }
}
