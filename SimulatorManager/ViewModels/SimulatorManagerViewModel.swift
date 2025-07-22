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
    private var folderMonitors: [AppFolderMonitor] = []
    private var cancellables: Set<AnyCancellable> = []
    private var deviceAppsSnapshots: [String: [String]] = [:] // Device UUID -> App Bundle IDs
    
    /// Maximum number of recent changes to keep
    private let maxRecentChanges = 20
    
    // MARK: - AppChange Types
    
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
    
    init(deviceManager: DeviceManager = DeviceManager()) {
        self.deviceManager = deviceManager
        bind()
        observeDevices()
    }
    
    func observeDevices() {
        folderMonitors = devices
            .compactMap {
                guard $0.hasAppsInstalled else { return nil }
                let monitor = AppFolderMonitor(device: $0)
                monitor.appfolderDidChange
                    .sink { [weak self] device in
                        os_log("\(device.name)'s folder did change.")
                        self?.handleDeviceAppFolderChange(device)
                    }
                    .store(in: &cancellables)
                return monitor
            }
        
        // Take initial snapshots of all devices
        devices.forEach { takeAppSnapshot(for: $0) }
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

// MARK: - App Change Handling

private extension SimulatorManagerViewModel {
    func handleDeviceAppFolderChange(_ device: Device) {
        // Update devices first
        deviceManager.updateDevices()
        
        // Wait a bit for the device manager to process changes, then detect app changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.detectAppChanges(for: device)
        }
    }
    
    func takeAppSnapshot(for device: Device) {
        let appBundleIds = device.apps.map(\.bundleIdentifier)
        deviceAppsSnapshots[device.udid] = appBundleIds
    }
    
    func detectAppChanges(for device: Device) {
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
            recentAppChanges.append(contentsOf: newChanges)
            recentAppChanges.sort { $0.timestamp > $1.timestamp }
            
            // Remove duplicates (same app on same device, keep most recent)
            recentAppChanges = removeDuplicateChanges(from: recentAppChanges)
            
            // Limit to max recent changes
            if recentAppChanges.count > maxRecentChanges {
                recentAppChanges = Array(recentAppChanges.prefix(maxRecentChanges))
            }
            
            // Update snapshot
            takeAppSnapshot(for: device)
        }
    }
    
    func createRemovedAppRepresentation(bundleId: String) -> any SimulatorApp {
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
    
    func removeDuplicateChanges(from changes: [AppChange]) -> [AppChange] {
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

// MARK: - Extensions

extension SimulatorManagerViewModel.AppChange: Identifiable {
    var id: String {
        "\(app.bundleIdentifier)-\(device.udid)-\(timestamp.timeIntervalSince1970)"
    }
}
