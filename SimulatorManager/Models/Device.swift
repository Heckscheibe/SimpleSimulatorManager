//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

enum DeviceState: Int, Decodable {
    case off = 1
    case running = 3
}

struct DeviceType: Comparable, Hashable, Identifiable {
    let id: String
    
    var name: String {
        id
    }
    
    static func < (lhs: DeviceType, rhs: DeviceType) -> Bool {
        return lhs.id < rhs.id
    }
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
    var folderPath: URL?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.udid = try container.decode(String.self, forKey: .udid)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastBootedAt = try container.decodeIfPresent(Date.self, forKey: .lastBootedAt)
        
        let rawRuntimeString = try container.decode(String.self, forKey: .runtime)
        let osPart = rawRuntimeString.components(separatedBy: ".").last?.components(separatedBy: "-")
        let osVersion = osPart?
            .enumerated()
            .reduce(into: "") { partialResult, osVersion in
                if osVersion.offset == 0 {
                    partialResult = osVersion.element
                } else if osVersion.offset == 1 {
                    partialResult.append(" \(osVersion.element)")
                } else if osVersion.offset == 2 {
                    partialResult.append(".\(osVersion.element)")
                }
            } ?? ""
        os_log("OSVersion: \(osVersion)")
        self.runtime = String(osVersion)
        self.state = try container.decode(DeviceState.self, forKey: .state)
    }
}

extension Device: Identifiable {
    var id: String {
        udid
    }
}
