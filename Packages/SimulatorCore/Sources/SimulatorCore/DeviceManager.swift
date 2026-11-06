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
public protocol DeviceManaging: AnyObject, Sendable {
    var deviceTypes: AnyPublisher<[DeviceType], Never> { get }
    var devices: AnyPublisher<[Device], Never> { get }
    var recentInstalledApps: AnyPublisher<[AppChange], Never> { get }

    func updateDevices()
    /// Reloads every device from disk off the main thread and publishes the result.
    /// Returns once the reloaded devices have been published, so callers can keep a
    /// progress indicator up for as long as the list is still stale.
    func resetAndLoadDevices() async
    /// Reloads the given device from disk off the main thread, publishes the result,
    /// and returns the refreshed device (or nil if reloading failed).
    @discardableResult
    func refreshDevice(_ device: Device) async -> Device?
    func getDevice(withUdid udid: String) -> Device?
    func updateRecentApps(_ changes: [AppChange])
    /// Whether UI test runner apps are left out of the recent-apps list. They are dropped before
    /// the list is capped, so they never take a slot from a real app, and changing this re-derives
    /// the published list without reloading anything.
    func setHidesTestRunnerApps(_ hides: Bool)
}

/// State lives in thread-safe `CurrentValueSubject`s; publisher values are only
/// mutated on the main queue, and background loading runs on a serial queue.
public class DeviceManager: ObservableObject, DeviceManaging, @unchecked Sendable {
    public var deviceTypes: AnyPublisher<[DeviceType], Never> {
        deviceTypesPublisher.eraseToAnyPublisher()
    }
    
    public var devices: AnyPublisher<[Device], Never> {
        devicesPublisher.eraseToAnyPublisher()
    }
    
    public var recentInstalledApps: AnyPublisher<[AppChange], Never> {
        recentInstalledAppsPublisher.eraseToAnyPublisher()
    }
    
    private let deviceTypesPublisher: CurrentValueSubject<[DeviceType], Never> = .init([])
    private let devicesPublisher: CurrentValueSubject<[Device], Never> = .init([])
    private let recentInstalledAppsPublisher: CurrentValueSubject<[AppChange], Never> = .init([])
    private var deviceTypeBinding: AnyCancellable?
    /// The recent-apps list before test runners are filtered out of it; see ``RecentApps/retained(from:limit:)``.
    /// Main-queue only, like the publishers.
    private var retainedRecentApps: [AppChange] = []
    private var hidesTestRunnerApps: Bool
    /// Serial queue for reloading single devices off the main thread.
    private let refreshQueue = DispatchQueue(label: "DeviceManager.refreshQueue", qos: .userInitiated)

    /// Reads devices from disk. `devicesDirectoryURL` is injectable so loading can be exercised
    /// against a fixture directory instead of the machine's own simulators.
    private let deviceLoader: DeviceLoader

    public init(
        devicesDirectoryURL: URL? = SimulatorPaths.coreSimulatorDevicesDirectoryURL(),
        hidesTestRunnerApps: Bool = false
    ) {
        self.hidesTestRunnerApps = hidesTestRunnerApps
        self.deviceLoader = DeviceLoader(devicesDirectoryURL: devicesDirectoryURL)
        loadDevices()
        bindDeviceTypes()
    }
    
    public func updateDevices() {
        loadDevices()
    }
    
    public func resetAndLoadDevices() async {
        // Reload off the main thread. A full load decodes every device, app and app-group plist
        // (a few thousand plists, ~1s on a typical install); running it inline on the caller froze
        // the menu bar UI for the duration of, for example, a cleanup deletion.
        let loadedDevices: DeviceLoader.LoadedDevices? = await withCheckedContinuation { continuation in
            refreshQueue.async { [weak self] in
                continuation.resume(returning: self?.deviceLoader.loadDevices())
            }
        }

        guard let loadedDevices else {
            return
        }

        // Publisher values are only mutated on the main queue (see the @unchecked Sendable note on
        // the type). DeviceManaging is Sendable, so a caller may invoke this off-main.
        await MainActor.run {
            // Replace rather than clear-then-refill: clearing up front would leave the menu
            // empty for the whole scan and collapse any open submenu. Device types are derived
            // from the devices publisher, so they follow automatically, and recent apps are
            // replaced wholesale by `populateInitialRecentApps`.
            publish(loadedDevices)
        }
    }
    
    @discardableResult
    public func refreshDevice(_ device: Device) async -> Device? {
        let udid = device.udid
        let existingURL = device.url

        let refreshedDevice: Device? = await withCheckedContinuation { continuation in
            refreshQueue.async { [weak self] in
                continuation.resume(returning: self?.deviceLoader.loadDevice(withUdid: udid, existingURL: existingURL))
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
    
    public func getDevice(withUdid udid: String) -> Device? {
        return devicesPublisher.value.first { $0.udid == udid }
    }
    
    public func setHidesTestRunnerApps(_ hides: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setHidesTestRunnerApps(hides)
            }
            return
        }
        guard hides != hidesTestRunnerApps else {
            return
        }

        hidesTestRunnerApps = hides
        publishRecentApps()
    }

    public func updateRecentApps(_ changes: [AppChange]) {
        // Publisher values are only mutated on the main queue (see the @unchecked Sendable
        // note on the type). DeviceManaging is Sendable, so a caller may invoke this off-main;
        // hop to main to keep the read-modify-write of the recent-apps list race-free.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateRecentApps(changes)
            }
            return
        }

        var currentInstalledApps = retainedRecentApps
        
        for change in changes {
            let appKey = RecentApps.key(for: change)

            switch change.changeType {
            case .installed:
                // Add the new installation
                currentInstalledApps.append(change)
            case .updated:
                // Remove the app if it exists, then add the updated version
                currentInstalledApps.removeAll { RecentApps.key(for: $0) == appKey }
                currentInstalledApps.append(change)
            case .removed:
                // Remove the app from installed apps
                currentInstalledApps.removeAll { RecentApps.key(for: $0) == appKey }
            }
        }

        // Sort by timestamp (most recent first)
        currentInstalledApps.sort { $0.timestamp > $1.timestamp }

        // Limit to max recent installed apps. Test runners are capped on their own, so hiding them
        // later cannot leave the list short and showing them again can bring them back.
        retainedRecentApps = RecentApps.retained(from: currentInstalledApps)
        publishRecentApps()
    }
}

// MARK: - Extensions

private extension DeviceManager {
    /// Populate initial recent apps from already installed apps
    func populateInitialRecentApps(_ appChanges: [AppChange]) {
        // Always assign, even when no apps were found: a reload has to replace whatever the
        // previous snapshot left behind, and doing it here keeps the whole recent-apps
        // replacement to a single emission.
        retainedRecentApps = RecentApps.retained(from: RecentApps.initial(from: appChanges, limit: .max))
        publishRecentApps()
    }

    func publishRecentApps() {
        recentInstalledAppsPublisher.value = RecentApps.visible(from: retainedRecentApps,
                                                                hidingTestRunners: hidesTestRunnerApps)
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
        guard let loadedDevices = deviceLoader.loadDevices() else {
            return
        }

        publish(loadedDevices)
    }

    /// Publishes a loaded snapshot. Must run on the main queue.
    func publish(_ loadedDevices: DeviceLoader.LoadedDevices) {
        devicesPublisher.value = loadedDevices.devices
        populateInitialRecentApps(loadedDevices.initialAppChanges)
    }
}
