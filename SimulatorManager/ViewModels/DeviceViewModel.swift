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
