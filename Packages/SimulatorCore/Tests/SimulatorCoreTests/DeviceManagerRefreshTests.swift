import Combine
import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

/// `refreshDevice` is the one place a single device's apps change, so it derives the recent-apps
/// changes itself. Before, only the folder monitor diffed, and a caller that refreshed the device
/// first (Erase Simulator) advanced the monitor's baseline, so the erased apps were never removed.
@Suite("DeviceManager single-device refresh")
@MainActor
struct DeviceManagerRefreshTests {
    private let udid = "55555555-5555-5555-5555-555555555555"
    private let otherUdid = "66666666-6666-6666-6666-666666666666"

    @Test("Refreshing an erased device drops its apps from Recent Apps")
    func erasedDeviceLeavesRecentApps() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeDevice(udid: otherUdid, name: "iPhone 16")
        try fixture.writeApp(bundleIdentifier: "com.example.first", name: "First", onDeviceWithUdid: udid)
        try fixture.writeApp(bundleIdentifier: "com.example.second", name: "Second", onDeviceWithUdid: udid)
        try fixture.writeApp(bundleIdentifier: "com.example.other", name: "Other", onDeviceWithUdid: otherUdid)

        let recorder = await Recorder(fixture: fixture)
        #expect(recorder.recentUdids.contains(udid))

        // What `simctl erase` leaves behind: the device folder without any app containers.
        try FileManager.default.removeItem(at: fixture.deviceURL(udid: udid)
            .appendingPathComponent(SimulatorPaths.dataFolderName)
            .appendingPathComponent("Containers"))

        let device = try #require(recorder.manager.getDevice(withUdid: udid))
        let refreshed = try #require(await recorder.manager.refreshDevice(device))

        #expect(refreshed.apps.isEmpty)
        #expect(!recorder.recentUdids.contains(udid))
        #expect(recorder.latestRecentApps.map(\.app.bundleIdentifier) == ["com.example.other"])
    }

    @Test("An app installed between refreshes is added once")
    func installAppearsOnce() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.first", name: "First", onDeviceWithUdid: udid)

        let recorder = await Recorder(fixture: fixture)
        try fixture.writeApp(bundleIdentifier: "com.example.new", name: "New", onDeviceWithUdid: udid)

        let device = try #require(recorder.manager.getDevice(withUdid: udid))
        try #require(await recorder.manager.refreshDevice(device) != nil)

        let identifiers = recorder.latestRecentApps.map(\.app.bundleIdentifier)
        #expect(identifiers.filter { $0 == "com.example.new" }.count == 1)
        #expect(Set(identifiers) == ["com.example.first", "com.example.new"])
    }

    @Test("A refresh that changes nothing leaves Recent Apps untouched")
    func unchangedRefreshDoesNotPublishRecentApps() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.first",
                             name: "First",
                             onDeviceWithUdid: udid,
                             modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let recorder = await Recorder(fixture: fixture)
        let emissionsBefore = recorder.recentAppsEmissions

        let device = try #require(recorder.manager.getDevice(withUdid: udid))
        try #require(await recorder.manager.refreshDevice(device) != nil)

        #expect(recorder.recentAppsEmissions == emissionsBefore)
        #expect(recorder.latestRecentApps.map(\.changeType) == [.installed])
    }
}

// MARK: - Helpers

@MainActor
private final class Recorder {
    let manager: DeviceManager

    private(set) var latestRecentApps: [AppChange] = []
    private(set) var recentAppsEmissions = 0
    private var cancellable: AnyCancellable?

    init(fixture: DeviceFixtureDirectory) async {
        manager = DeviceManager(devicesDirectoryURL: fixture.url)
        await manager.waitForInitialLoad()
        cancellable = manager.recentInstalledApps.sink { [weak self] changes in
            self?.latestRecentApps = changes
            self?.recentAppsEmissions += 1
        }
    }

    var recentUdids: Set<String> {
        Set(latestRecentApps.map(\.device.udid))
    }
}
