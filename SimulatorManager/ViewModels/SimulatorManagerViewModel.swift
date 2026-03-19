//
//  SimulatorManagerViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.23.
//

import Foundation
import AppKit
import Combine
import Observation
import os

@MainActor
@Observable
class SimulatorManagerViewModel: FolderOpening {
    var deviceTypes: [DeviceType] = []
    var devices: [Device] = []
    var recentAppChanges: [AppChange] = []
    var recentInstalledApps: [AppChange] = []
    
    @ObservationIgnored private let deviceManager: DeviceManaging
    @ObservationIgnored private let simulatorResetService: SimulatorResetServing
    @ObservationIgnored private let deviceAppMonitoringService: DeviceAppMonitoring
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    
    init(
        deviceManager: DeviceManaging,
        simulatorResetService: SimulatorResetServing = SimulatorResetService(),
        deviceAppMonitoringService: DeviceAppMonitoring? = nil
    ) {
        self.deviceManager = deviceManager
        self.simulatorResetService = simulatorResetService
        self.deviceAppMonitoringService = deviceAppMonitoringService ?? DeviceAppMonitoringService(deviceManager: deviceManager)
        bind()
    }

    func makeDeviceViewModel(for device: Device) -> DeviceViewModel {
        DeviceViewModel(
            device: device,
            deviceManager: deviceManager,
            simulatorResetService: simulatorResetService
        )
    }
}

private extension SimulatorManagerViewModel {
    func bind() {
        deviceManager.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.devices = devices
            }
            .store(in: &cancellables)
        
        deviceManager.deviceTypes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceTypes in
                self?.deviceTypes = deviceTypes
            }
            .store(in: &cancellables)
        
        deviceManager.recentInstalledApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recentInstalledApps in
                self?.recentInstalledApps = recentInstalledApps
                self?.recentAppChanges = recentInstalledApps
            }
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
