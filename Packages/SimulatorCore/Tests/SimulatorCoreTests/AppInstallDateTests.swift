import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

@Suite("App install date")
struct AppInstallDateTests {
    private let udid = "11111111-1111-1111-1111-111111111111"
    private let installed = Date(timeIntervalSince1970: 1_700_000_000)
    private let launched = Date(timeIntervalSince1970: 1_700_500_000)

    private func loadApp(from fixture: DeviceFixtureDirectory) throws -> any SimulatorApp {
        let loaded = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices())

        return try #require(loaded.devices.first?.apps.first)
    }

    private func makeFixture() throws -> DeviceFixtureDirectory {
        let fixture = try DeviceFixtureDirectory()
        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")

        return fixture
    }

    @Test("The install date is the bundle's modification date")
    func installDateIsBundleDate() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example",
                             onDeviceWithUdid: udid, bundleModifiedAt: installed, containerModifiedAt: installed)

        let app = try loadApp(from: fixture)

        #expect(app.bundleModifiedAt == installed)
    }

    @Test("An app that writes to its container does not have its install date advance")
    func launchingDoesNotAdvanceInstallDate() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example",
                             onDeviceWithUdid: udid, bundleModifiedAt: installed, containerModifiedAt: launched)

        let app = try loadApp(from: fixture)

        #expect(app.bundleModifiedAt == installed)
        // The change-detection date keeps its existing meaning: the newer of the two.
        #expect(app.contentModifiedAt == launched)
    }

    @Test("Reinstalling an app advances its install date")
    func reinstallAdvancesInstallDate() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let installedApp = try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example",
                                                onDeviceWithUdid: udid, modifiedAt: installed)
        #expect(try loadApp(from: fixture).bundleModifiedAt == installed)

        try FileManager.default.setAttributes([.modificationDate: launched],
                                              ofItemAtPath: installedApp.bundleURL.path)

        #expect(try loadApp(from: fixture).bundleModifiedAt == launched)
    }

    @Test("Repeated loads of an unchanged app yield the same install date")
    func installDateIsStableAcrossLoads() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example",
                             onDeviceWithUdid: udid, modifiedAt: installed)

        let dates = try (0 ..< 3).map { _ in try loadApp(from: fixture).bundleModifiedAt }

        #expect(Set(dates) == [installed])
    }

    @Test("The recent-apps timestamp still follows the newer of bundle and container")
    func recentAppsTimestampUnchanged() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example",
                             onDeviceWithUdid: udid, bundleModifiedAt: installed, containerModifiedAt: launched)

        let loaded = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices())

        #expect(loaded.initialAppChanges.first?.timestamp == launched)
    }

    @Test("A model without a bundle date reports none rather than a placeholder")
    func missingBundleDateIsNil() {
        let app = SimulatoriOSApp(displayName: "Example",
                                  bundleIdentifier: "com.example.app",
                                  appDocumentsFolderURL: nil,
                                  appPackageURL: nil,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [])

        #expect(app.bundleModifiedAt == nil)
    }
}
