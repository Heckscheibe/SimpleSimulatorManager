//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

enum SimulatorPlatform {
    case iPhone
    case iPad
    case watch
    case appleTV
    case visionPro
    case iPodTouch
}

class Device: DecodableURLContainer {
    static let devicePlistName = "device.plist"
    static let appGroupFolderPath = "data/Containers/Shared/AppGroup"
    
    enum CodingKeys: String, CodingKey {
        case udid = "UDID"
        case name
        case lastBootedAt
        case runtime
        case state
        case deviceType
    }
    
    let udid: String
    let name: String
    let lastBootedAt: Date?
    let runtime: String
    let deviceType: String
    let state: DeviceState
    
    // not decoded properties
    var appContainerFolder: URL? {
        url?.appendingPathComponent("data/Containers/Data/Application")
    }
    
    var appGroupsFolder: URL? {
        url?.appendingPathComponent(Device.appGroupFolderPath)
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
    
    var simulatorPlatform: SimulatorPlatform {
        if deviceType.contains("iPhone") {
            return .iPhone
        } else if deviceType.contains("iPad") {
            return .iPad
        } else if deviceType.contains("Apple-Vision-Pro") {
            return .visionPro
        } else if deviceType.contains("Apple-TV") {
            return .appleTV
        } else if deviceType.contains("Apple-Watch") {
            return .watch
        } else {
            return .iPodTouch
        }
    }
    
    @Published var apps: [any SimulatorApp] = []
    @Published var appGroups: [AppGroup] = []
    @Published var hasAppsInstalled: Bool = true
    var url: URL?
}

extension Device: Identifiable {
    var id: String {
        udid
    }
}
