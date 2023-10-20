//
//  SimulatorManagerViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation
import os

class SimulatorManagerViewModel {
    @Published var deviceTypes: [DeviceType]
    @Published var devices: [Device]
    
    let deviceManager = DeviceManager()
    
    init() {
        deviceTypes = deviceManager.deviceTypes
        devices = deviceManager.devices
    }
    
    func didSelectApp(app: SimulatorApp) {
        os_log("Did select: \(app.displayName)")
    }
}
