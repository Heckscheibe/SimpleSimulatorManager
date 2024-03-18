//
//  SimulatorManagerViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation
import os
import AppKit
import Combine

class SimulatorManagerViewModel: ObservableObject {
    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    
    private let deviceManager = DeviceManager()
    private var folderMonitors: [AppFolderMonitor] = []
    private var cancellables: [AnyCancellable] = []
    
    init() {
        bind()
        observeDevices()
    }
    
    func observeDevices() {
        folderMonitors = devices.compactMap {
            guard $0.hasAppsInstalled else { return nil }
            let monitor = AppFolderMonitor(device: $0)
            monitor.appfolderDidChange
                .sink { [weak self] device in
                    os_log("\(device.name)'s folder did change.")
                    self?.deviceManager.update(device: device)
                }
                .store(in: &cancellables)
            return monitor
        }
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
    func bind() {
        deviceManager.devices
            .assign(to: \.devices, on: self)
            .store(in: &cancellables)
        
        deviceManager.deviceTypes
            .assign(to: \.deviceTypes, on: self)
            .store(in: &cancellables)
    }
}

extension SimulatorManagerViewModel: FolderOpening {}
