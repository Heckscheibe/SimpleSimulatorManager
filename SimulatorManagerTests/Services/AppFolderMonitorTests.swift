//
//  AppFolderMonitorTests.swift
//  SimulatorManagerTests
//

import Combine
import Foundation
import Testing
@testable import SimulatorCore
@testable import SimulatorManager

@Suite("AppFolderMonitor", .serialized)
@MainActor
struct AppFolderMonitorTests {
    /// A device whose `data` folder exists but has no app installed yet, like a freshly booted simulator.
    private func makeDeviceWithoutApps() throws -> (device: Device, root: URL) {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("AppFolderMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("data/Library/Caches"),
                                                withIntermediateDirectories: true)

        let device = TestDataHelpers.createMockDevice()
        device.url = root
        return (device, root)
    }

    /// Simulates the background writes a booted simulator makes outside the app containers.
    private func writeNoise(into device: Device, every interval: Duration, for duration: Duration) async throws {
        let caches = try #require(device.dataFolder).appendingPathComponent("Library/Caches")
        let deadline = ContinuousClock.now + duration
        var index = 0

        while ContinuousClock.now < deadline {
            try "noise".write(to: caches.appendingPathComponent("file-\(index % 5).txt"), atomically: true, encoding: .utf8)
            index += 1
            try? await Task.sleep(for: interval)
        }
    }

    @Test("Background writes outside the app packages folder do not emit")
    func ignoresBackgroundWritesWithoutApps() async throws {
        let (device, root) = try makeDeviceWithoutApps()
        defer { try? FileManager.default.removeItem(at: root) }

        let monitor = AppFolderMonitor(device: device)
        #expect(monitor.isWatchingFallback)
        #expect(monitor.isMonitoring)

        var emissions = 0
        let subscription = monitor.appfolderDidChange.sink { _ in emissions += 1 }
        defer { subscription.cancel() }

        // Stop the noise early so an unfiltered watch would have had time to fire after the 3 s debounce.
        try await writeNoise(into: device, every: .milliseconds(200), for: .seconds(1))
        try? await Task.sleep(for: .seconds(4))

        #expect(emissions == 0)
    }

    @Test("The first install is reported while the simulator keeps writing elsewhere")
    func reportsFirstInstallDespiteBackgroundWrites() async throws {
        let (device, root) = try makeDeviceWithoutApps()
        defer { try? FileManager.default.removeItem(at: root) }

        let monitor = AppFolderMonitor(device: device)
        #expect(monitor.isWatchingFallback)

        var emittedDevice: Device?
        let subscription = monitor.appfolderDidChange.sink { emittedDevice = $0 }
        defer { subscription.cancel() }

        // Noise keeps going for longer than the debounce after the install, which is what used to
        // reset the debounce forever.
        async let noise: Void = writeNoise(into: device, every: .milliseconds(200), for: .seconds(6))

        try? await Task.sleep(for: .milliseconds(500))
        let appFolder = try #require(device.appPackagesFolder)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Test.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try "plist".write(to: appFolder.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        await waitUntil(timeout: .seconds(6)) { emittedDevice != nil }
        try await noise

        #expect(emittedDevice?.udid == device.udid)
    }
}
