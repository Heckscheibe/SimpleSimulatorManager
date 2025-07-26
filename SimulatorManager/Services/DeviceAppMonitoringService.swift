//
//  DeviceAppMonitoringService.swift
//  SimulatorManager
//
//  Created by AI Assistant on 11.07.25.
//

import Foundation
import Combine
import os

// MARK: - Protocol

/// Protocol defining the interface for device app monitoring
protocol DeviceAppMonitoringServiceProtocol: AnyObject {
    func stopMonitoring()
}

/// Service that monitors simulator app changes and integrates with DeviceManager
class DeviceAppMonitoringService: ObservableObject, DeviceAppMonitoringServiceProtocol {
    // MARK: - Properties
    
    private let deviceManager: DeviceManagerProtocol
    private var appFolderMonitors: [String: AppFolderMonitor] = [:] // UUID -> Monitor
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManagerProtocol) {
        self.deviceManager = deviceManager
        setupDeviceMonitoring()
    }
    
    // MARK: - Public Methods
    func stopMonitoring() {
        // Clear all monitors which will stop monitoring
        appFolderMonitors.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupDeviceMonitoring() {
        // Monitor device changes to update folder monitors
        deviceManager.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.updateMonitorsForDevices(devices)
            }
            .store(in: &cancellables)
    }
    
    private func updateMonitorsForDevices(_ devices: [Device]) {
        // Remove monitors for devices that no longer exist
        let currentDeviceUUIDs = Set(devices.map(\.udid))
        let monitorsToRemove = appFolderMonitors.keys.filter { !currentDeviceUUIDs.contains($0) }
        
        for uuid in monitorsToRemove {
            appFolderMonitors.removeValue(forKey: uuid)
        }
        
        // Add or update monitors for new/existing devices
        for device in devices {
            updateMonitorForDevice(device)
        }
    }
    
    private func updateMonitorForDevice(_ device: Device) {
        // Only create monitor if device has app container folder and we don't already have one
        guard device.appContainerFolder != nil,
              appFolderMonitors[device.udid] == nil else {
            return
        }
        
        let monitor = AppFolderMonitor(device: device)
        
        monitor.appfolderDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changedDevice in
                self?.handleDeviceAppFolderChange(changedDevice)
            }
            .store(in: &cancellables)
        
        appFolderMonitors[device.udid] = monitor
    }
    
    private func handleDeviceAppFolderChange(_ device: Device) {
        // Refresh only the specific device's apps when its app container folder changes
        let previousApps = device.apps
        deviceManager.updateSpecificDevice(device)
        
        // Get the updated device to compare changes
        guard let updatedDevice = deviceManager.getDevice(withUdid: device.udid) else {
            return
        }
        
        let currentApps = updatedDevice.apps
        let previousAppIds = Set(previousApps.map(\.bundleIdentifier))
        let currentAppIds = Set(currentApps.map(\.bundleIdentifier))
        
        var newChanges: [AppChange] = []
        
        // Detect newly installed apps
        let newAppIds = currentAppIds.subtracting(previousAppIds)
        for newAppId in newAppIds {
            if let app = currentApps.first(where: { $0.bundleIdentifier == newAppId }) {
                let change = AppChange(
                    app: app,
                    device: updatedDevice,
                    changeType: .installed,
                    timestamp: Date()
                )
                newChanges.append(change)
            }
        }
        
        // Detect removed apps
        let removedAppIds = previousAppIds.subtracting(currentAppIds)
        for removedAppId in removedAppIds {
            if let removedApp = previousApps.first(where: { $0.bundleIdentifier == removedAppId }) {
                let change = AppChange(
                    app: removedApp,
                    device: updatedDevice,
                    changeType: .removed,
                    timestamp: Date()
                )
                newChanges.append(change)
            }
        }
        
        // Propagate changes to DeviceManager
        if !newChanges.isEmpty {
            deviceManager.addAppChanges(newChanges)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}
