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
}
