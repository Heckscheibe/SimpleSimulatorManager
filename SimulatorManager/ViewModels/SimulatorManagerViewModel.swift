//
//  SimulatorManagerViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation
import os
import AppKit

class SimulatorManagerViewModel {
    @Published var deviceTypes: [DeviceType]
    @Published var devices: [Device]
    
    let deviceManager = DeviceManager()
    
    init() {
        deviceTypes = deviceManager.deviceTypes
        devices = deviceManager.devices
    }
    
    func didSelectSimulatorFolder(for device: Device) {
        guard let url = device.url else {
            return
        }
        openFolderAt(url)
    }
    
    func didSelectAppsFolder(for device: Device) {
        guard let url = device.url?.appendingPathComponent(SimulatorPaths.appDataPath) else {
            return
        }
        openFolderAt(url)
    }
}

private extension SimulatorManagerViewModel {
    func openFolderAt(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}