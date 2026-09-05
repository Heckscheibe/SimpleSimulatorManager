//
//  MenuTreeFixture.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
@preconcurrency import Combine
@testable import SimulatorManager

/// Wires up everything `MenuTreeBuilder` needs, against mocks, so a test can describe a menu state
/// and read back the tree it produces.
@MainActor
final class MenuTreeFixture {
    let deviceManager: MockDeviceManager
    let settings: Settings
    let simulatorManagerViewModel: SimulatorManagerViewModel
    let settingsViewModel: SettingsViewModel
    let cleanupViewModel: CleanupSimulatorsViewModel
    let resetViewModel: ResetSimulatorsViewModel
    let githubService = GithubService()

    private(set) var openPreferencesCount = 0
    private(set) var quitCount = 0

    /// A throwaway defaults suite per fixture, so a test can flip preferences without touching the
    /// user's own — or another test's — state.
    private let suiteName: String

    init(resetService: any SimulatorResetServing = MockSimulatorDeviceActionService()) {
        let suiteName = "MenuTreeBuilderTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults?.removePersistentDomain(forName: suiteName)

        let deviceManager = MockDeviceManager()
        let settings = Settings(userDefaults: userDefaults)
        let simulatorManagerViewModel = SimulatorManagerViewModel(
            deviceManager: deviceManager,
            simulatorResetService: resetService,
            deviceAppMonitoringService: MockDeviceAppMonitoringService()
        )

        self.suiteName = suiteName
        self.deviceManager = deviceManager
        self.settings = settings
        self.simulatorManagerViewModel = simulatorManagerViewModel
        settingsViewModel = SettingsViewModel(settings: settings,
                                              simulatorManagerViewModel: simulatorManagerViewModel)
        cleanupViewModel = CleanupSimulatorsViewModel(cleanupService: MockSimulatorCleanupService(),
                                                      deviceManager: deviceManager,
                                                      destructiveActionConfirmer: MockDestructiveActionConfirmer())
        resetViewModel = ResetSimulatorsViewModel(deviceManager: deviceManager,
                                                  simulatorResetService: resetService)
    }

    func makeBuilder(appVersion: String? = "1.4.0") -> MenuTreeBuilder {
        MenuTreeBuilder(simulatorManagerViewModel: simulatorManagerViewModel,
                        settingsViewModel: settingsViewModel,
                        cleanupViewModel: cleanupViewModel,
                        resetViewModel: resetViewModel,
                        settings: settings,
                        githubService: githubService,
                        appVersion: appVersion,
                        openPreferences: { [weak self] in self?.openPreferencesCount += 1 },
                        quit: { [weak self] in self?.quitCount += 1 })
    }

    /// The mock publishes devices and device types independently, so both have to be set — the real
    /// `DeviceManager` derives the types from the devices.
    func setDevices(_ devices: [Device]) async {
        let deviceTypes = Set(devices.map { DeviceType(id: $0.name, simulatorPlatform: $0.simulatorPlatform) })

        deviceManager.setMockDevices(devices)
        deviceManager.setMockDeviceTypes(deviceTypes.sorted())
        await settle()
    }

    func setRecentApps(_ recentApps: [AppChange]) async {
        deviceManager.setMockRecentInstalledApps(recentApps)
        await settle()
    }

    /// The view model binds with `.receive(on: DispatchQueue.main)`, so values land a main-queue
    /// turn later. Draining turns keeps this deterministic instead of sleeping for a guessed delay.
    func settle(turns: Int = 3) async {
        for _ in 0 ..< turns {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }

    func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Tree lookup

extension MenuNode {
    /// Depth-first lookup by identifier, so a test can reach a node without walking the tree by
    /// hand at every level.
    func descendant(withID identifier: String) -> MenuNode? {
        if id == identifier {
            return self
        }

        for child in children {
            if let match = child.descendant(withID: identifier) {
                return match
            }
        }

        return nil
    }
}

extension [MenuNode] {
    var identifiers: [String] {
        map(\.id)
    }

    var titles: [String] {
        map(\.title)
    }

    func node(withID identifier: String) -> MenuNode? {
        lazy.compactMap { $0.descendant(withID: identifier) }.first
    }
}

// MARK: - Gated reset service

/// A reset service that suspends inside `shutDownAndEraseSimulator` until it is released, so a test
/// can observe the menu while a device action is genuinely in flight.
final class GatedResetService: SimulatorResetServing, @unchecked Sendable {
    nonisolated var didResetAllSimulators: AnyPublisher<Void, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<Void, Never>()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func shutDownAndEraseSimulator(deviceUdid: String) async {
        await withCheckedContinuation { continuation in
            lock.lock()

            guard !isReleased else {
                lock.unlock()
                continuation.resume()

                return
            }

            self.continuation = continuation
            lock.unlock()
        }
    }

    func shutDownAllSimulators() {}

    func resetAllSimulators() {
        subject.send()
    }

    func shutDownAndResetAllSimulators() {
        subject.send()
    }

    /// Lets a suspended erase finish. Safe to call before the erase starts.
    func release() {
        lock.lock()
        isReleased = true
        let pending = continuation
        continuation = nil
        lock.unlock()

        pending?.resume()
    }
}
