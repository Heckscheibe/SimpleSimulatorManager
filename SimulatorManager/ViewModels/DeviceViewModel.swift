//
//  DeviceViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class DeviceViewModel: ObservableObject, FolderOpening {
    @Published var device: Device
    
    init(device: Device) {
        self.device = device
    }
    
    // MARK: - Device Properties
    
    var hasAppsInstalled: Bool {
        device.hasAppsInstalled
    }
    
    var osVersion: String {
        device.osVersion
    }
    
    var apps: [any SimulatorApp] {
        device.apps
    }
    
    var appGroups: [AppGroup] {
        device.appGroups
    }
    
    // MARK: - Folder Existence Checks
    
    var hasAppsFolder: Bool {
        guard let url = device.appDataFolder else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var hasAppPackagesFolder: Bool {
        guard let url = device.appPackagesFolder else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
