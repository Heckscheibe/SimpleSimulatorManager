//
//  SimulatorAppChangeService.swift
//  SimulatorManager
//
//  Created by AI Assistant on 11.07.25.
//

import Foundation
import Combine
import os

/// Service that monitors simulator app changes and integrates with existing DeviceManager
class SimulatorAppChangeService: ObservableObject {
    // MARK: - Types
    
    struct AppChange {
        let app: any SimulatorApp
        let device: Device
        let changeType: ChangeType
        let timestamp: Date
    }
    
    enum ChangeType {
        case installed
        case removed
    }
    
    // MARK: - Properties
    
    @Published var recentChanges: [AppChange] = []
    
    private let deviceManager: DeviceManager
    private var appFolderMonitors: [String: AppFolderMonitor] = [:] // UUID -> Monitor
    private var cancellables = Set<AnyCancellable>()
    private var deviceAppsSnapshots: [String: [String]] = [:] // Device UUID -> App Bundle IDs
    
    /// Maximum number of recent changes to keep
    private let maxRecentChanges = 20
    
    // MARK: - Initialization
    
    init(deviceManager: DeviceManager) {
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
            deviceAppsSnapshots.removeValue(forKey: uuid)
        }
        
        // Add or update monitors for new/existing devices
        for device in devices {
            updateMonitorForDevice(device)
            takeAppSnapshot(for: device)
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
    
    private func takeAppSnapshot(for device: Device) {
        let appBundleIds = device.apps.map(\.bundleIdentifier)
        deviceAppsSnapshots[device.udid] = appBundleIds
    }
    
    private func handleDeviceAppFolderChange(_ device: Device) {
        // Refresh only the specific device's apps when its app container folder changes
        deviceManager.updateSpecificDevice(device)
        
        // Wait a bit for the device to process changes, then detect changes with updated device
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Get the updated device from the device manager
            if let updatedDevice = self?.deviceManager.getDevice(withUdid: device.udid) {
                self?.detectAppChanges(for: updatedDevice)
            }
        }
    }
    
    private func detectAppChanges(for device: Device) {
        let previousApps = Set(deviceAppsSnapshots[device.udid] ?? [])
        let currentApps = Set(device.apps.map(\.bundleIdentifier))
        
        var newChanges: [AppChange] = []
        
        // Detect newly installed apps
        let newAppIds = currentApps.subtracting(previousApps)
        for newAppId in newAppIds {
            if let app = device.apps.first(where: { $0.bundleIdentifier == newAppId }) {
                let change = AppChange(
                    app: app,
                    device: device,
                    changeType: .installed,
                    timestamp: Date()
                )
                newChanges.append(change)
            }
        }
        
        // Detect removed apps
        let removedAppIds = previousApps.subtracting(currentApps)
        for removedAppId in removedAppIds {
            // Create a minimal app representation for removed apps
            let removedApp = createRemovedAppRepresentation(bundleId: removedAppId)
            let change = AppChange(
                app: removedApp,
                device: device,
                changeType: .removed,
                timestamp: Date()
            )
            newChanges.append(change)
        }
        
        if !newChanges.isEmpty {
            // Add new changes and sort by timestamp (most recent first)
            recentChanges.append(contentsOf: newChanges)
            recentChanges.sort { $0.timestamp > $1.timestamp }
            
            // Remove duplicates (same app on same device, keep most recent)
            recentChanges = removeDuplicateChanges(from: recentChanges)
            
            // Limit to max recent changes
            if recentChanges.count > maxRecentChanges {
                recentChanges = Array(recentChanges.prefix(maxRecentChanges))
            }
            
            // Update snapshot
            takeAppSnapshot(for: device)
        }
    }
    
    private func createRemovedAppRepresentation(bundleId: String) -> any SimulatorApp {
        // Create a minimal representation for removed apps
        return SimulatoriOSApp(
            displayName: "Removed App",
            bundleIdentifier: bundleId,
            appDocumentsFolderURL: nil,
            appPackageURL: nil,
            hasWatchApp: false,
            hasUserDefaults: false
        )
    }
    
    private func removeDuplicateChanges(from changes: [AppChange]) -> [AppChange] {
        var seen: Set<String> = []
        var uniqueChanges: [AppChange] = []
        
        for change in changes {
            let key = "\(change.app.bundleIdentifier)-\(change.device.udid)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueChanges.append(change)
            }
        }
        
        return uniqueChanges
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Extensions

extension SimulatorAppChangeService.AppChange: Identifiable {
    var id: String {
        "\(app.bundleIdentifier)-\(device.udid)-\(timestamp.timeIntervalSince1970)"
    }
}
