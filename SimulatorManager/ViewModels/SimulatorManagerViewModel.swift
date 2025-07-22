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
    @Published var recentAppChanges: [AppChange] = []
    
    private let deviceManager: DeviceManager
    private let deviceAppMonitoringService: DeviceAppMonitoringService
    private var cancellables: Set<AnyCancellable> = []
    
    init(deviceManager: DeviceManager = DeviceManager()) {
        self.deviceManager = deviceManager
        self.deviceAppMonitoringService = DeviceAppMonitoringService(deviceManager: deviceManager)
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
        
        deviceManager.recentAppChanges
            .assign(to: \.recentAppChanges, on: self)
            .store(in: &cancellables)
    }
}

extension SimulatorManagerViewModel: FolderOpening {}
