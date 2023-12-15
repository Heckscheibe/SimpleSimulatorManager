//
//  SimulatorManagerViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation
import os
import AppKit

class SimulatorManagerViewModel: ObservableObject {
    @Published var deviceTypes: [DeviceType]
    @Published var devices: [Device]
    
    let deviceManager = DeviceManager()
    let monitor: FolderMonitor
    
    init() {
        deviceTypes = deviceManager.deviceTypes
        devices = deviceManager.devices
        monitor = FolderMonitor(url: deviceManager.devices.first!.url!)
        observe()
    }
    
    func observe() {
        monitor.folderDidChange = {
            os_log("Folder changed")
        }
        monitor.startMonitoring()
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
