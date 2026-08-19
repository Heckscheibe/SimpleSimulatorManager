//
//  DeviceAppMonitoringService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.07.25.
//

import Combine
import Foundation
import os

// MARK: - Protocol

/// Protocol defining the interface for device app monitoring
@MainActor
protocol DeviceAppMonitoring: AnyObject {
    func resetMonitoring()
}

/// Service that monitors simulator app changes and integrates with DeviceManager.
/// All monitor callbacks are delivered on the main queue, so the whole service is main-actor-isolated.
@MainActor
class DeviceAppMonitoringService: ObservableObject, DeviceAppMonitoring {
    // MARK: - Types

    /// Bundles a monitor with its change subscription so both share one lifetime.
    private struct MonitoredDevice {
        let monitor: AppFolderMonitor
        let subscription: AnyCancellable
    }

    // MARK: - Properties

    private let deviceManager: DeviceManaging
    private var monitoredDevices: [String: MonitoredDevice] = [:] // UDID -> Monitor
    private var devicesSubscription: AnyCancellable?

    // MARK: - Initialization

    init(deviceManager: DeviceManaging) {
        self.deviceManager = deviceManager
        setupDeviceMonitoring()
    }

    // MARK: - Public Methods

    func resetMonitoring() {
        stopMonitoring()
        setupDeviceMonitoring()
    }

    // MARK: - Change Detection

    /// Diffs two app snapshots of a device into installed/updated/removed changes.
    /// An app only counts as updated when its content modification date moved forward,
    /// so unrelated apps on the same device don't flood the recent-apps list.
    nonisolated static func computeAppChanges(
        previousApps: [any SimulatorApp],
        currentApps: [any SimulatorApp],
        device: Device,
        now: Date = Date()
    ) -> [AppChange] {
        // Two containers can share a bundle identifier (a stale install plus a fresh one),
        // so keep the most-recently-modified entry rather than trapping on duplicate keys.
        let previousAppsById = Dictionary(previousApps.map { ($0.bundleIdentifier, $0) },
                                          uniquingKeysWith: Self.mostRecentlyModified)
        let currentAppsById = Dictionary(currentApps.map { ($0.bundleIdentifier, $0) },
                                         uniquingKeysWith: Self.mostRecentlyModified)

        var changes: [AppChange] = []

        for (bundleIdentifier, currentApp) in currentAppsById {
            guard let previousApp = previousAppsById[bundleIdentifier] else {
                changes.append(AppChange(app: currentApp,
                                         device: device,
                                         changeType: .installed,
                                         timestamp: currentApp.contentModifiedAt ?? now))
                continue
            }

            if let previousDate = previousApp.contentModifiedAt,
               let currentDate = currentApp.contentModifiedAt,
               currentDate > previousDate {
                changes.append(AppChange(app: currentApp,
                                         device: device,
                                         changeType: .updated,
                                         timestamp: currentDate))
            }
        }

        for (bundleIdentifier, previousApp) in previousAppsById where currentAppsById[bundleIdentifier] == nil {
            changes.append(AppChange(app: previousApp,
                                     device: device,
                                     changeType: .removed,
                                     timestamp: now))
        }

        return changes
    }

    /// Tie-breaker for two apps sharing a bundle identifier: prefer the newer container.
    private nonisolated static func mostRecentlyModified(_ lhs: any SimulatorApp, _ rhs: any SimulatorApp) -> any SimulatorApp {
        (rhs.contentModifiedAt ?? .distantPast) > (lhs.contentModifiedAt ?? .distantPast) ? rhs : lhs
    }

    // MARK: - Private Methods

    private func stopMonitoring() {
        devicesSubscription = nil
        monitoredDevices.removeAll()
    }

    private func setupDeviceMonitoring() {
        // Monitor device changes to update folder monitors
        devicesSubscription = deviceManager.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.updateMonitorsForDevices(devices)
            }
    }

    private func updateMonitorsForDevices(_ devices: [Device]) {
        // Remove monitors for devices that no longer exist
        let currentDeviceUDIDs = Set(devices.map(\.udid))
        let monitorsToRemove = monitoredDevices.keys.filter { !currentDeviceUDIDs.contains($0) }

        for udid in monitorsToRemove {
            monitoredDevices.removeValue(forKey: udid)
        }

        // Add monitors for new devices, and re-point existing monitors at the freshly published
        // `Device`. A full reload (`resetAndLoadDevices`) replaces every instance in place of the
        // old clear-then-refill, so nothing else would rebuild them: a monitor left holding the
        // pre-reload snapshot diffs the next folder change against a stale app list and
        // re-reports apps the reload already recorded as installed.
        for device in devices {
            if monitoredDevices[device.udid] != nil {
                refreshMonitor(for: device)
            } else {
                updateMonitorForDevice(device)
            }
        }
    }

    private func updateMonitorForDevice(_ device: Device) {
        // Only create monitor if device has app container folder and we don't already have one
        guard device.appDataFolder != nil,
              monitoredDevices[device.udid] == nil else {
            return
        }

        let monitor = AppFolderMonitor(device: device)

        // Don't cache a monitor that failed to start (or had no folder to watch): the guard
        // above would then block any retry forever. Leaving it uncached lets the next
        // device-list publish attempt monitoring again.
        guard monitor.isMonitoring else {
            os_log("Monitoring did not start for device %@; will retry on next update", device.udid)
            return
        }

        let subscription = monitor.appfolderDidChange
            .sink { [weak self] changedDevice in
                self?.handleDeviceAppFolderChange(changedDevice)
            }

        monitoredDevices[device.udid] = MonitoredDevice(monitor: monitor, subscription: subscription)
    }

    private func handleDeviceAppFolderChange(_ device: Device) {
        // The monitor stays alive across the refresh (FSEvents survives folder changes), so there
        // is no unmonitored window. `device` is the monitor's current snapshot, so its apps are the
        // correct baseline for the diff.
        let previousApps = device.apps

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            // Refresh only the specific device's apps when its app container folder changes.
            guard let updatedDevice = await self.deviceManager.refreshDevice(device) else {
                // Device was removed or could not be reloaded; leave the existing monitor as-is.
                // A genuinely removed device's monitor is torn down on the next device-list publish.
                return
            }

            self.refreshMonitor(for: updatedDevice)

            let changes = Self.computeAppChanges(previousApps: previousApps,
                                                 currentApps: updatedDevice.apps,
                                                 device: updatedDevice)

            if !changes.isEmpty {
                self.deviceManager.updateRecentApps(changes)
            }
        }
    }

    /// Advance the monitor's device snapshot in place, recreating it only when the watch target
    /// must change — i.e. the fallback data-folder watch is upgraded to a packages-folder watch
    /// once the first app is installed.
    private func refreshMonitor(for device: Device) {
        guard let monitored = monitoredDevices[device.udid] else {
            // No monitor (e.g. device briefly dropped out); create one from scratch.
            updateMonitorForDevice(device)
            return
        }

        if monitored.monitor.isWatchingFallback,
           let packagesFolder = device.appPackagesFolder,
           FileManager.default.directoryExistsAtURL(packagesFolder) {
            monitoredDevices.removeValue(forKey: device.udid)
            updateMonitorForDevice(device)
        } else {
            monitored.monitor.update(device: device)
        }
    }
}
