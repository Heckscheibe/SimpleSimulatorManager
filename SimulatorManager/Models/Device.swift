//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

class Device: ObservableObject, DecodableURLContainer {
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
    
    /// not decoded properties
    var dataFolder: URL? {
        url?.appendingPathComponent(SimulatorPaths.dataFolderName)
    }
    
    var appDataFolder: URL? {
        dataFolder?.appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
    }
    
    var appPackagesFolder: URL? {
        dataFolder?.appendingPathComponent(SimulatorPaths.appBundleApplicationsPath)
    }
    
    var appGroupsFolder: URL? {
        url?.appendingPathComponent(SimulatorPaths.appGroupsPath)
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
        osVersion = SimulatorPaths.formattedOSVersion(from: runtime)
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
}

extension Device: Identifiable {
    var id: String {
        udid
    }
}
