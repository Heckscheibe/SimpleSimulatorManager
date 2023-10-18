//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

struct Device: DecodableURLContainer {
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
    var url: URL?
    
    var hasAppsInstalled: Bool {
        guard let url else { return false }
        return FileManager.default.directoryExistsAtURL(url.appending(path: "data/Containers"))
    }
    
    var osVersion: String {
        runtime.components(separatedBy: ".").last?
            .components(separatedBy: "-")
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
    }
}

extension Device: Identifiable {
    var id: String {
        udid
    }
}
