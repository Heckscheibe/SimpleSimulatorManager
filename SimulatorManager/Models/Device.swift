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
    
    // not decoded properties
    var url: URL?
    var apps: [SimulatorApp] = []
    var appContainerFolder: URL? {
        url?.appendingPathComponent("data/Containers")
    }
    
    var hasAppsInstalled: Bool {
        guard let appContainerFolder else { return false }
        return FileManager.default.directoryExistsAtURL(appContainerFolder)
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
