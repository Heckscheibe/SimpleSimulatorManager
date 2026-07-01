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
        let previousAppsById = Dictionary(uniqueKeysWithValues: previousApps.map { ($0.bundleIdentifier, $0) })
        let currentAppsById = Dictionary(uniqueKeysWithValues: currentApps.map { ($0.bundleIdentifier, $0) })

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

        // Add monitors for new devices
        for device in devices {
            updateMonitorForDevice(device)
        }
    }

    private func updateMonitorForDevice(_ device: Device) {
        // Only create monitor if device has app container folder and we don't already have one
        guard device.appDataFolder != nil,
              monitoredDevices[device.udid] == nil else {
            return
        }

        let monitor = AppFolderMonitor(device: device)

        let subscription = monitor.appfolderDidChange
            .sink { [weak self] changedDevice in
                self?.handleDeviceAppFolderChange(changedDevice)
            }

        monitoredDevices[device.udid] = MonitoredDevice(monitor: monitor, subscription: subscription)
    }

    private func handleDeviceAppFolderChange(_ device: Device) {
        // Remove and recreate the monitor for this device to ensure we're monitoring the correct folder
        monitoredDevices.removeValue(forKey: device.udid)

        let previousApps = device.apps

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            // Refresh only the specific device's apps when its app container folder changes
            guard let updatedDevice = await self.deviceManager.refreshDevice(device) else {
                // Keep watching with the stale device rather than losing monitoring entirely
                self.updateMonitorForDevice(device)
                return
            }

            self.updateMonitorForDevice(updatedDevice)

            let changes = Self.computeAppChanges(previousApps: previousApps,
                                                 currentApps: updatedDevice.apps,
                                                 device: updatedDevice)

            if !changes.isEmpty {
                self.deviceManager.updateRecentApps(changes)
            }
        }
    }
}
