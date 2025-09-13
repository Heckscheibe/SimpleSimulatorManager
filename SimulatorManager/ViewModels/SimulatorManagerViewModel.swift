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
    
    private let deviceManager: DeviceManaging
    private let simulatorResetService: SimulatorResetService
    private let deviceAppMonitoringService: DeviceAppMonitoring
    private var cancellables: Set<AnyCancellable> = []
    
    init(deviceManager: DeviceManaging,
         simulatorResetService: SimulatorResetService) {
        self.deviceManager = deviceManager
        self.simulatorResetService = simulatorResetService
        self.deviceAppMonitoringService = DeviceAppMonitoringService(deviceManager: deviceManager)
        bind()
    }
}

private extension SimulatorManagerViewModel {
    func bind() {
        deviceManager.devices
            .receive(on: DispatchQueue.main)
            .assign(to: \.devices, on: self)
            .store(in: &cancellables)
        
        deviceManager.deviceTypes
            .receive(on: DispatchQueue.main)
            .assign(to: \.deviceTypes, on: self)
            .store(in: &cancellables)
        
        deviceManager.recentInstalledApps
            .receive(on: DispatchQueue.main)
            .assign(to: \.recentInstalledApps, on: self)
            .store(in: &cancellables)
        
        simulatorResetService.didResetAllSimulators
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.deviceManager.resetAndLoadDevices()
//                self?.deviceAppMonitoringService.resetMonitoring()
            }
            .store(in: &cancellables)
    }
}
