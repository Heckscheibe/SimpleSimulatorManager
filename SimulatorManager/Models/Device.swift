//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

class Device: ObservableObject, DecodableURLContainer {
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
    let state: DeviceState
    let simulatorPlatform: SimulatorPlatform
    let osVersion: String
    
    // not decoded properties
    var appDataFolder: URL? {
        url?.appendingPathComponent("data/Containers/Data/Application")
    }
    
    var appPackagesFolder: URL? {
        url?.appendingPathComponent("data/Containers/Bundle/Application")
    }
    
    var appGroupsFolder: URL? {
        url?.appendingPathComponent(Device.appGroupFolderPath)
    }
    
    var hasAppsInstalled: Bool {
        !apps.isEmpty
    }
    
    @Published var apps: [any SimulatorApp] = []
    @Published var appGroups: [AppGroup] = []
    
    var url: URL?
    
    // MARK: - Custom Decoder
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        udid = try container.decode(String.self, forKey: .udid)
        name = try container.decode(String.self, forKey: .name)
        lastBootedAt = try container.decodeIfPresent(Date.self, forKey: .lastBootedAt)
        let runtime = try container.decode(String.self, forKey: .runtime)
        let deviceType = try container.decode(String.self, forKey: .deviceType)
        state = try container.decode(DeviceState.self, forKey: .state)
        
        // Determine simulatorPlatform and osVersion based on decoded values
        simulatorPlatform = SimulatorPlatform(from: deviceType)
        osVersion = Device.extractOSVersion(from: runtime)
    }
    
    // MARK: - Custom Initializer
    
    init(udid: String, name: String, state: DeviceState, simulatorPlatform: SimulatorPlatform, osVersion: String) {
        self.udid = udid
        self.name = name
        self.lastBootedAt = nil
        self.osVersion = osVersion
        self.simulatorPlatform = simulatorPlatform
        self.state = state
    }
    
    // MARK: - Helper Methods
    
    private static func extractOSVersion(from runtime: String) -> String {
        return runtime.components(separatedBy: ".").last?
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
