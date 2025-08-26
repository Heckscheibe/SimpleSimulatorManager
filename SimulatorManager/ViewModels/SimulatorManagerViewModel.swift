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
    @Published var isResettingSimulators = false
    
    private let deviceManager: DeviceManagerProtocol
    private let deviceAppMonitoringService: DeviceAppMonitoringServiceProtocol
    private let simulatorResetService: SimulatorResetServiceProtocol
    private var cancellables: Set<AnyCancellable> = []
    
    init(deviceManager: DeviceManagerProtocol = DeviceManager(),
         deviceAppMonitoringService: DeviceAppMonitoringServiceProtocol? = nil,
         simulatorResetService: SimulatorResetServiceProtocol = SimulatorResetService()) {
        self.deviceManager = deviceManager
        self.deviceAppMonitoringService = deviceAppMonitoringService ?? DeviceAppMonitoringService(deviceManager: deviceManager)
        self.simulatorResetService = simulatorResetService
        bind()
    }
    
    @MainActor func resetAllSimulators() {
        guard !isResettingSimulators else { return }
        
        isResettingSimulators = true
        
        Task {
            do {
                try await simulatorResetService.shutDownAndResetAllSimulators()
                os_log("Successfully reset all simulators")
            } catch {
                os_log("Failed to reset simulators: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                isResettingSimulators = false
            }
        }
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
