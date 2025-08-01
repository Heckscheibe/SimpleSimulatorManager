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

class SimulatorManagerViewModel: ObservableObject, FolderOpening {
    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    @Published var recentAppChanges: [AppChange] = []
    @Published var recentInstalledApps: [AppChange] = []
    
    private let deviceManager: DeviceManagerProtocol
    private let deviceAppMonitoringService: DeviceAppMonitoringServiceProtocol
    private var cancellables: Set<AnyCancellable> = []
    
    init(deviceManager: DeviceManagerProtocol = DeviceManager(),
         deviceAppMonitoringService: DeviceAppMonitoringServiceProtocol? = nil) {
        self.deviceManager = deviceManager
        self.deviceAppMonitoringService = deviceAppMonitoringService ?? DeviceAppMonitoringService(deviceManager: deviceManager)
        bind()
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
        
        deviceManager.recentInstalledApps
            .assign(to: \.recentInstalledApps, on: self)
            .store(in: &cancellables)
    }
}
