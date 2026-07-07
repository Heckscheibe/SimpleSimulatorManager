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

/// Protocol defining the interface for device management.
/// Conformers must be safe to use across isolation domains because device refreshes
/// are awaited from the main actor while loading happens in the background.
protocol DeviceManaging: AnyObject, Sendable {
    var deviceTypes: AnyPublisher<[DeviceType], Never> { get }
    var devices: AnyPublisher<[Device], Never> { get }
    var recentInstalledApps: AnyPublisher<[AppChange], Never> { get }

    func updateDevices()
    func resetAndLoadDevices()
    /// Reloads the given device from disk off the main thread, publishes the result,
    /// and returns the refreshed device (or nil if reloading failed).
    @discardableResult
    func refreshDevice(_ device: Device) async -> Device?
    func getDevice(withUdid udid: String) -> Device?
    func updateRecentApps(_ changes: [AppChange])
}

/// State lives in thread-safe `CurrentValueSubject`s; publisher values are only
/// mutated on the main queue, and background loading runs on a serial queue.
class DeviceManager: ObservableObject, DeviceManaging, @unchecked Sendable {
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
    /// Serial queue for reloading single devices off the main thread.
    private let refreshQueue = DispatchQueue(label: "DeviceManager.refreshQueue", qos: .userInitiated)
    
    /// Maximum number of recent installed apps to keep
    private let maxRecentInstalledApps = 20
    
    init() {
        loadDevices()
        bindDeviceTypes()
    }
    
    func updateDevices() {
        loadDevices()
    }
    
    func resetAndLoadDevices() {
        devicesPublisher.value.removeAll()
        deviceTypesPublisher.value.removeAll()
        recentInstalledAppsPublisher.value.removeAll()
        loadDevices()
    }
    
    @discardableResult
    func refreshDevice(_ device: Device) async -> Device? {
        let udid = device.udid
        let existingURL = device.url

        let refreshedDevice: Device? = await withCheckedContinuation { continuation in
            refreshQueue.async { [weak self] in
                continuation.resume(returning: self?.loadDevice(withUdid: udid, existingURL: existingURL))
            }
        }

        guard let refreshedDevice else {
            os_log("Failed to refresh simulator with udid %@", udid)
            return nil
        }

        // If the device left the list while we were reloading (erased/removed), don't
        // resurrect it — publish nothing and report the refresh as failed so callers
        // stop tracking it instead of recreating monitors for a gone device.
        let didApply = await MainActor.run { () -> Bool in
            guard devicesPublisher.value.contains(where: { $0.udid == refreshedDevice.udid }) else {
                return false
            }

            devicesPublisher.value = devicesPublisher.value.map { device in
                device.udid == refreshedDevice.udid ? refreshedDevice : device
            }
            return true
        }

        return didApply ? refreshedDevice : nil
    }
    
    func getDevice(withUdid udid: String) -> Device? {
        return devicesPublisher.value.first { $0.udid == udid }
    }
    
    func updateRecentApps(_ changes: [AppChange]) {
        // Publisher values are only mutated on the main queue (see the @unchecked Sendable
        // note on the type). DeviceManaging is Sendable, so a caller may invoke this off-main;
        // hop to main to keep the read-modify-write of the recent-apps list race-free.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateRecentApps(changes)
            }
            return
        }

        var currentInstalledApps = recentInstalledAppsPublisher.value
        
        for change in changes {
            let appKey = "\(change.app.bundleIdentifier)-\(change.device.udid)"
            
            switch change.changeType {
            case .installed:
                // Add the new installation
                currentInstalledApps.append(change)
            case .updated:
                // Remove the app if it exists, then add the updated version
                currentInstalledApps.removeAll { existingChange in
                    let existingKey = "\(existingChange.app.bundleIdentifier)-\(existingChange.device.udid)"
                    return existingKey == appKey
                }
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
}

// MARK: - Extensions

private extension DeviceManager {
    var simulatorFolderURL: URL? {
        SimulatorPaths.coreSimulatorDevicesDirectoryURL()
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
    
    /// Populate initial recent apps from already installed apps
    func populateInitialRecentApps(_ appChanges: [AppChange]) {
        guard !appChanges.isEmpty else {
            return
        }

        // Sort by timestamp (most recent first)
        let sortedChanges = appChanges.sorted { $0.timestamp > $1.timestamp }

        // Limit to max recent installed apps
        let limitedChanges = Array(sortedChanges.prefix(maxRecentInstalledApps))

        // Remove duplicates (keep most recent for each app/device combination)
        let uniqueChanges = removeDuplicateChanges(from: limitedChanges)

        recentInstalledAppsPublisher.value = uniqueChanges
    }
    
    func bindDeviceTypes() {
        // A single-device refresh re-emits the whole devices array; the device *set* is usually
        // unchanged, so removeDuplicates avoids recomputing and re-publishing identical device
        // types (and the downstream UI invalidation) on every app-folder change.
        deviceTypeBinding = devicesPublisher.map { Set($0.map { DeviceType(id: $0.name,
                                                                           simulatorPlatform: $0.simulatorPlatform) }).sorted() }
            .removeDuplicates()
            .assign(to: \.deviceTypesPublisher.value, on: self)
    }
    
    func loadDevices() {
        guard let url = simulatorFolderURL else {
            return
        }

        let urls = getContentOfDirectoryAt(url: url)

        let newDevices: [Device] = urls.reduce(into: []) { devices, url in
            let url = url.appendingPathComponent(SimulatorPaths.devicePlistName)
                
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
            let appsAndTimeStamps = appDiscoveryService.loadAppsAndTimestamps(for: device)
            device.apps = appsAndTimeStamps.apps
            device.appGroups = appDiscoveryService.loadAppGroups(for: device)
            
            // Load apps with timestamps for initial recent apps
            let appChanges = appsAndTimeStamps.appChanges
            allInitialAppChanges.append(contentsOf: appChanges)
        }
        
        // Populate initial recent apps
        populateInitialRecentApps(allInitialAppChanges)
    }

    func loadDevice(withUdid udid: String, existingURL: URL?) -> Device? {
        guard let deviceDirectoryURL = existingURL ?? simulatorFolderURL?.appendingPathComponent(udid) else {
            os_log("Missing simulator directory for udid %@", udid)
            return nil
        }

        let devicePlistURL = deviceDirectoryURL.appendingPathComponent(SimulatorPaths.devicePlistName)

        do {
            let device = try CustomPropertyListDecoder().decode(Device.self, at: devicePlistURL)
            device.apps = appDiscoveryService.loadApps(for: device)
            device.appGroups = appDiscoveryService.loadAppGroups(for: device)
            return device
        } catch {
            os_log("Failed to reload device with udid %@ due to error %@", udid, String(describing: error))
            return nil
        }
    }
    
    func getContentOfDirectoryAt(url: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(url) else {
            return []
        }
        
        do {
            return try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
        } catch {
            os_log("Failed to get content at path \(url) due to error \(error)")
            return []
        }
    }
}
