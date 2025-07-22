//
//  DeviceManager.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import Combine
import os

enum SimulatorPaths {
    static let appPackagePath = "data/Containers/Bundle/Application"
    static let appDataPath = "data/Containers/Data/Application"
    static let userDefaultsPath = "Library/Preferences"
}

class DeviceManager: ObservableObject {
    var deviceTypes: AnyPublisher<[DeviceType], Never> {
        deviceTypesPublisher.eraseToAnyPublisher()
    }
    
    var devices: AnyPublisher<[Device], Never> {
        devicesPublisher.eraseToAnyPublisher()
    }
    
    var recentAppChanges: AnyPublisher<[AppChange], Never> {
        recentAppChangesPublisher.eraseToAnyPublisher()
    }
    
    private let deviceTypesPublisher: CurrentValueSubject<[DeviceType], Never> = .init([])
    private let devicesPublisher: CurrentValueSubject<[Device], Never> = .init([])
    private let recentAppChangesPublisher: CurrentValueSubject<[AppChange], Never> = .init([])
    private var deviceTypeBinding: AnyCancellable?
    private let appDiscoveryService = AppDiscoveryService()
    
    /// Maximum number of recent changes to keep
    private let maxRecentChanges = 20
    
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
    
    func addAppChanges(_ changes: [AppChange]) {
        var currentChanges = recentAppChangesPublisher.value
        currentChanges.append(contentsOf: changes)
        
        // Sort by timestamp (most recent first)
        currentChanges.sort { $0.timestamp > $1.timestamp }
        
        // Remove duplicates manually (same app on same device, keep most recent)
        currentChanges = removeDuplicateChanges(from: currentChanges)
        
        // Limit to max recent changes
        if currentChanges.count > maxRecentChanges {
            currentChanges = Array(currentChanges.prefix(maxRecentChanges))
        }
        
        recentAppChangesPublisher.value = currentChanges
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
        
        newDevices.forEach {
            appDiscoveryService.loadApps(for: $0)
            appDiscoveryService.loadAppGroups(for: $0)
        }
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
