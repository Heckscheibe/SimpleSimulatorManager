//
//  DeviceManager.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import Combine
import os

// MARK: - Protocols

/// Protocol defining the interface for device management
protocol DeviceManagerProtocol: AnyObject {
    var deviceTypes: AnyPublisher<[DeviceType], Never> { get }
    var devices: AnyPublisher<[Device], Never> { get }
    var recentInstalledApps: AnyPublisher<[AppChange], Never> { get }
    
    func updateDevices()
    func updateSpecificDevice(_ updatedDevice: Device)
    func getDevice(withUdid udid: String) -> Device?
    func updateRecentApps(_ changes: [AppChange])
}

enum SimulatorPaths {
    static let appPackagePath = "data/Containers/Bundle/Application"
    static let appDataPath = "data/Containers/Data/Application"
    static let userDefaultsPath = "Library/Preferences"
}

class DeviceManager: ObservableObject, DeviceManagerProtocol {
    var deviceTypes: AnyPublisher<[DeviceType], Never> {
        deviceTypesPublisher.eraseToAnyPublisher()
    }
    
    var devices: AnyPublisher<[Device], Never> {
        devicesPublisher.eraseToAnyPublisher()
    }
    
    var recentInstalledApps: AnyPublisher<[AppChange], Never> {
        recentInstalledAppsPublisher.eraseToAnyPublisher()
    }
    
    private let deviceTypesPublisher: CurrentValueSubject<[DeviceType], Never> = .init([])
    private let devicesPublisher: CurrentValueSubject<[Device], Never> = .init([])
    private let recentInstalledAppsPublisher: CurrentValueSubject<[AppChange], Never> = .init([])
    private var deviceTypeBinding: AnyCancellable?
    private let appDiscoveryService = AppDiscoveryService()
    
    /// Maximum number of recent installed apps to keep
    private let maxRecentInstalledApps = 20
    
    init() {
        loadDevices()
        bindDeviceTypes()
    }
    
    func updateDevices() {
        loadDevices()
    }
    
    func updateSpecificDevice(_ updatedDevice: Device) {
        // Reload apps for the specific device
        appDiscoveryService.loadApps(for: updatedDevice)
        appDiscoveryService.loadAppGroups(for: updatedDevice)
        
        // Update the device in the devices array
        let currentDevices = devicesPublisher.value
        let updatedDevices = currentDevices.map { device in
            device.udid == updatedDevice.udid ? updatedDevice : device
        }
        devicesPublisher.value = updatedDevices
    }
    
    func getDevice(withUdid udid: String) -> Device? {
        return devicesPublisher.value.first { $0.udid == udid }
    }
    
    func updateRecentApps(_ changes: [AppChange]) {
        var currentInstalledApps = recentInstalledAppsPublisher.value
        
        for change in changes {
            let appKey = "\(change.app.bundleIdentifier)-\(change.device.udid)"
            
            switch change.changeType {
            case .installed:
                // Remove any existing entry for this app/device combination
                currentInstalledApps.removeAll { existingChange in
                    let existingKey = "\(existingChange.app.bundleIdentifier)-\(existingChange.device.udid)"
                    return existingKey == appKey
                }
                // Add the new installation
                currentInstalledApps.append(change)
                
            case .removed:
                // Remove the app from installed apps
                currentInstalledApps.removeAll { existingChange in
                    let existingKey = "\(existingChange.app.bundleIdentifier)-\(existingChange.device.udid)"
                    return existingKey == appKey
                }
            }
        }
        
        // Sort by timestamp (most recent first)
        currentInstalledApps.sort { $0.timestamp > $1.timestamp }
        
        // Limit to max recent installed apps
        if currentInstalledApps.count > maxRecentInstalledApps {
            currentInstalledApps = Array(currentInstalledApps.prefix(maxRecentInstalledApps))
        }
        
        recentInstalledAppsPublisher.value = currentInstalledApps
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
    
    /// Populate initial recent apps from already installed apps
    private func populateInitialRecentApps(_ appChanges: [AppChange]) {
        guard !appChanges.isEmpty else { return }
        
        // Sort by timestamp (most recent first)
        let sortedChanges = appChanges.sorted { $0.timestamp > $1.timestamp }
        
        // Limit to max recent installed apps
        let limitedChanges = Array(sortedChanges.prefix(maxRecentInstalledApps))
        
        // Remove duplicates (keep most recent for each app/device combination)
        let uniqueChanges = removeDuplicateChanges(from: limitedChanges)
        
        recentInstalledAppsPublisher.value = uniqueChanges
    }
}

// MARK: - Extensions

private extension DeviceManager {
    var simulatorFolderURL: URL? {
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return libraryPath.first?.appending(path: "Developer/CoreSimulator/Devices")
    }
    
    func bindDeviceTypes() {
        deviceTypeBinding = devicesPublisher.map { Set($0.map { DeviceType(id: $0.name,
                                                                           simulatorPlatform: $0.simulatorPlatform) }).sorted() }
            .assign(to: \.deviceTypesPublisher.value, on: self)
    }
    
    func loadDevices() {
        guard let url = simulatorFolderURL else { return }
        let urls = getContentOfDirectoryAt(url: url)

        let newDevices: [Device] = urls.reduce(into: []) { devices, url in
            let url = url.appendingPathComponent(Device.devicePlistName)
                
            do {
                let device = try CustomPropertyListDecoder().decode(Device.self, at: url)
                devices.append(device)
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(url)")
            }
        }
        devicesPublisher.value = newDevices
        
        // Load apps and collect initial recent apps
        var allInitialAppChanges: [AppChange] = []
        
        newDevices.forEach { device in
            appDiscoveryService.loadApps(for: device)
            appDiscoveryService.loadAppGroups(for: device)
            
            // Load apps with timestamps for initial recent apps
            let appChanges = appDiscoveryService.loadAppsWithTimestamps(for: device)
            allInitialAppChanges.append(contentsOf: appChanges)
        }
        
        // Populate initial recent apps
        populateInitialRecentApps(allInitialAppChanges)
    }
    
    func getContentOfDirectoryAt(url: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(url) else {
            return []
        }
        
        do {
            let urls = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            return urls
        } catch {
            os_log("Failed to get content at path \(url) due to error \(error)")
            return []
        }
    }
}
