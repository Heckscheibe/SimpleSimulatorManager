//
//  DeviceLoader.swift
//  SimulatorCore
//

import Foundation
import os

/// Reads simulator devices, their apps and app groups from the CoreSimulator devices directory.
///
/// Pure disk work: it touches no publisher or other shared state, so it is safe to call from any
/// thread. ``DeviceManager`` publishes what it loads; consumers without a UI can call it directly.
public struct DeviceLoader: Sendable {
    /// Devices and their initial app changes, produced in one pass so the whole result can be
    /// published at once.
    public struct LoadedDevices: Sendable {
        public let devices: [Device]
        public let initialAppChanges: [AppChange]
    }

    /// Root of the CoreSimulator device directories. Injectable so loading can be exercised
    /// against a fixture directory instead of the machine's own simulators.
    public let devicesDirectoryURL: URL?

    private let appDiscoveryService: AppDiscoveryService

    public init(
        devicesDirectoryURL: URL? = SimulatorPaths.coreSimulatorDevicesDirectoryURL(),
        appDiscoveryService: AppDiscoveryService = AppDiscoveryService()
    ) {
        self.devicesDirectoryURL = devicesDirectoryURL
        self.appDiscoveryService = appDiscoveryService
    }

    /// Decodes every device's metadata without scanning its apps or app groups — the cheap call
    /// for listing devices. Devices whose `device.plist` is missing or unreadable are skipped.
    public func loadDeviceList() -> [Device] {
        guard let devicesDirectoryURL else {
            return []
        }

        return appDiscoveryService.getContentOfDirectoryAt(url: devicesDirectoryURL).reduce(into: []) { devices, url in
            let url = url.appendingPathComponent(SimulatorPaths.devicePlistName)

            do {
                let device = try CustomPropertyListDecoder().decode(Device.self, at: url)
                devices.append(device)
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(url)")
            }
        }
    }

    /// Decodes every device plus its apps and app groups, along with an `.installed` change per
    /// app for seeding the recent-apps list. Returns nil when the devices directory is unknown.
    /// - Parameter includingAppGroups: Pass `false` to skip scanning app groups when only apps are
    ///   needed; the devices' `appGroups` then stay empty.
    public func loadDevices(includingAppGroups: Bool = true) -> LoadedDevices? {
        guard devicesDirectoryURL != nil else {
            return nil
        }

        let devices = loadDeviceList()
        var initialAppChanges: [AppChange] = []

        for device in devices {
            let appsAndTimeStamps = appDiscoveryService.loadAppsAndTimestamps(for: device)
            device.apps = appsAndTimeStamps.apps
            if includingAppGroups {
                device.appGroups = appDiscoveryService.loadAppGroups(for: device)
            }
            initialAppChanges.append(contentsOf: appsAndTimeStamps.appChanges)
        }

        return LoadedDevices(devices: devices, initialAppChanges: initialAppChanges)
    }

    /// Reloads a single device with its apps and app groups.
    /// - Parameter existingURL: The device's folder, when already known; otherwise it is derived
    ///   from `udid` inside the devices directory.
    public func loadDevice(withUdid udid: String, existingURL: URL? = nil) -> Device? {
        guard let deviceDirectoryURL = existingURL ?? devicesDirectoryURL?.appendingPathComponent(udid) else {
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
}
