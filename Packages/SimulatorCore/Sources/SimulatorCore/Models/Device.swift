//
//  Device.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import os

public class Device: ObservableObject, DecodableURLContainer {
    enum CodingKeys: String, CodingKey {
        case udid = "UDID"
        case name
        case lastBootedAt
        case runtime
        case state
        case deviceType
    }
    
    public let udid: String
    public let name: String
    public let lastBootedAt: Date?
    public let state: DeviceState
    public let simulatorPlatform: SimulatorPlatform
    public let osVersion: String
    
    /// not decoded properties
    public var dataFolder: URL? {
        url?.appendingPathComponent(SimulatorPaths.dataFolderName)
    }
    
    public var appDataFolder: URL? {
        dataFolder?.appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
    }
    
    public var appPackagesFolder: URL? {
        dataFolder?.appendingPathComponent(SimulatorPaths.appBundleApplicationsPath)
    }
    
    public var appGroupsFolder: URL? {
        url?.appendingPathComponent(SimulatorPaths.appGroupsPath)
    }
    
    public var hasAppsInstalled: Bool {
        !apps.isEmpty
    }
    
    @Published public var apps: [any SimulatorApp] = []
    @Published public var appGroups: [AppGroup] = []
    
    public var url: URL?
    
    // MARK: - Custom Decoder
    
    public required init(from decoder: Decoder) throws {
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
    
    public init(udid: String, name: String, state: DeviceState, simulatorPlatform: SimulatorPlatform, osVersion: String) {
        self.udid = udid
        self.name = name
        self.lastBootedAt = nil
        self.osVersion = osVersion
        self.simulatorPlatform = simulatorPlatform
        self.state = state
    }
}

extension Device: Identifiable {
    public var id: String {
        udid
    }
}

/// Devices are populated during discovery before they are shared; once published
/// they are only mutated on the main queue.
extension Device: @unchecked Sendable {}
