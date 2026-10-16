import Combine
import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

/// Covers the recent-apps rule in `DeviceManager.updateRecentApps`: entries are keyed by bundle
/// identifier plus device UDID, so a change on one device never touches another device's entry.
@Suite("DeviceManager recent apps")
struct DeviceManagerRecentAppsTests {
    @Test("Removing an app on one device keeps the same app on another device")
    @MainActor
    func removalIsScopedToTheDevice() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let deviceManager = DeviceManager(devicesDirectoryURL: fixture.url)
        var cancellables: Set<AnyCancellable> = []
        var recentApps: [AppChange] = []

        deviceManager.recentInstalledApps
            .sink { recentApps = $0 }
            .store(in: &cancellables)

        let erasedDevice = TestDataHelpers.createMockDevice(udid: "device-1")
        let otherDevice = TestDataHelpers.createMockDevice(udid: "device-2")
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.shared")

        deviceManager.updateRecentApps([
            TestDataHelpers.createMockAppChange(app: app, device: erasedDevice, changeType: .installed),
            TestDataHelpers.createMockAppChange(app: app, device: otherDevice, changeType: .installed)
        ])
        #expect(recentApps.count == 2)

        deviceManager.updateRecentApps([
            TestDataHelpers.createMockAppChange(app: app, device: erasedDevice, changeType: .removed)
        ])

        #expect(recentApps.count == 1)
        #expect(recentApps.first?.device.udid == "device-2")
        #expect(recentApps.first?.app.bundleIdentifier == "com.test.shared")
        cancellables.removeAll()
    }
}
